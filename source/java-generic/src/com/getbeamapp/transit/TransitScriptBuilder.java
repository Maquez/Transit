package com.getbeamapp.transit;

import java.lang.reflect.Array;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.json.JSONObject;

public class TransitScriptBuilder {
    private static class ArgumentList extends LinkedList<Object> {

        private static final long serialVersionUID = -8245671519808766593L;

    }

    public static Iterable<Object> arguments(Object... items) {
        ArgumentList result = new ArgumentList();

        for (Object item : items) {
            result.add(item);
        }

        return result;
    }

    private StringBuffer buffer;
    private final StringBuffer vars = new StringBuffer();
    private final Set<String> definedVars = new HashSet<String>();
    private final String QUOTE = "\"";
    private String result = null;
    private final String thisArgExpression;

    public TransitScriptBuilder(String transitVariable, Object thisArg) {
        buffer = new StringBuffer();

        if (thisArg == null || thisArg instanceof TransitContext) {
            this.thisArgExpression = null;
        } else {
            parse(thisArg);
            this.thisArgExpression = buffer.toString();
        }

        this.buffer = new StringBuffer();
    }

    public void process(String stringToEvaluate, Object... values) {
        Pattern pattern = Pattern.compile("(.*?)@");
        Matcher matcher = pattern.matcher(stringToEvaluate);

        int index = 0;

        while (matcher.find()) {
            buffer.append(matcher.group(1));

            if (index >= values.length) {
                matcher.appendReplacement(buffer, "@");
                continue;
            } else {
                parse(values[index]);
                matcher.appendReplacement(buffer, "");
            }

            index++;
        }

        matcher.appendTail(buffer);
    }

    public String toScript() {
        if (result != null) {
            return result;
        }

        StringBuffer output = new StringBuffer();
        boolean hasVars = !definedVars.isEmpty();

        if (hasVars) {
            output.append("(function() {\n  ");
            output.append(vars);
            output.append(";\n  return ");
        }

        if (thisArgExpression != null) {
            output.append("(function() {\n    return ");
            output.append(buffer);
            output.append(";\n  }).call(");
            output.append(thisArgExpression);
            output.append(")");
        } else {
            output.append(buffer);
        }

        if (hasVars) {
            output.append(";\n");
            output.append("})()");
        }

        result = output.toString();
        return result;
    }

    private void addVariable(String variableName, String... strings) {
        if (!definedVars.contains(variableName)) {
            if (definedVars.size() == 0) {
                vars.append("var ");
            } else {
                vars.append(", ");
            }

            definedVars.add(variableName);

            vars.append(variableName);
            vars.append(" = ");

            for (String string : strings) {
                vars.append(string);
            }
        }

        buffer.append(variableName);
    }

    private void parse(Object o) {
        if (o instanceof JSRepresentable) {
            buffer.append(((JSRepresentable) o).getJSRepresentation());
        } else if (o instanceof TransitProxy) {
            TransitProxy p = (TransitProxy) o;

            if (p instanceof TransitNativeFunction) {
                TransitNativeFunction f = (TransitNativeFunction) p;
                addVariable(getVariable(f), "transit.nativeFunction(", QUOTE, f.getNativeId(), QUOTE, ")");
            } else if (p.getProxyId() != null) {
                addVariable(getVariable(p), "transit.retained[", QUOTE, p.getProxyId(), QUOTE, "]");
            } else {
                parseNative(o);
            }
        } else if (o instanceof TransitContext) {
            buffer.append("window");
        } else {
            parseNative(o);
        }
    }

    private void parseNative(Object o) {
        if (o == null) {
            buffer.append("null");
        } else if (o.getClass().isArray()) {
            parseArray(o);
        } else if (o instanceof Iterable<?>) {
            parse((Iterable<?>) o);
        } else if (o instanceof TransitJSObject || o instanceof Map<?, ?>) {
            parse((Map<?, ?>) o);
        } else if (o instanceof Number || o instanceof Boolean) {
            buffer.append(String.valueOf(o));
        } else if (o instanceof String) {
            buffer.append(JSONObject.quote((String) o));
        } else {
            throw new IllegalArgumentException(String.format("Can't convert %s to JavaScript. Try to implement %s.",
                    o.getClass().getCanonicalName(),
                    JSRepresentable.class.getCanonicalName()));
        }
    }

    private void parseArray(Object array) {
        int l = Array.getLength(array);
        List<Object> list = new ArrayList<Object>(l);

        for (int i = 0; i < l; i++) {
            list.add(Array.get(array, i));
        }

        parse(list);
    }

    private void parse(Map<?, ?> o) {
        buffer.append("{");

        boolean first = true;
        for (Object key : o.keySet()) {
            if (first) {
                first = false;
            } else {
                buffer.append(", ");
            }

            buffer.append(JSONObject.quote(key.toString()));
            buffer.append(": ");

            parse(o);
        }

        buffer.append("}");
    }

    private void parse(Iterable<?> iterable) {
        if (!(iterable instanceof ArgumentList)) {
            buffer.append("[");
        }

        boolean first = true;
        for (Object o : iterable) {
            if (first) {
                first = false;
            } else {
                buffer.append(", ");
            }
            
            parse(o);
        }

        if (!(iterable instanceof ArgumentList)) {
            buffer.append("]");
        }
    }

    private String getVariable(TransitProxy p) {
        if (p instanceof TransitNativeFunction) {
            TransitNativeFunction f = (TransitNativeFunction) p;
            return "__TRANSIT_NATIVE_FUNCTION_" + f.getNativeId();
        } else if (p instanceof TransitJSFunction) {
            return "__TRANSIT_JS_FUNCTION_" + p.getProxyId();
        } else {
            return "__TRANSIT_OBJECT_PROXY_" + p.getProxyId();
        }
    }
}