//
//  Transit.m
//  TransitTestsIOS
//
//  Created by Heiko Behrens on 08.02.13.
//  Copyright (c) 2013 BeamApp. All rights reserved.
//

#import "Transit.h"
#import "Transit+Private.h"
#import "SBJson.h"

@implementation TransitJSDirectExpression

-(id)initWithExpression:(NSString*)expression {
    self = [self init];
    if(self) {
        _expression = expression;
    }
    return self;
}

-(NSString*)jsRepresentation{
    return _expression;
}

+(id)expression:(NSString*)expression {
    return [[self alloc] initWithExpression:expression];
}

@end

@implementation NSString(TransRegExp)

-(NSString*)stringByReplacingMatchesOf:(NSRegularExpression*)regex withTransformation:(NSString*(^)(NSString*element)) block {

    NSMutableString* mutableString = [self mutableCopy];
    NSInteger offset = 0;

    for (NSTextCheckingResult* result in [regex matchesInString:self options:0 range:NSMakeRange(0, self.length)]) {
        
        NSRange resultRange = [result range];
        resultRange.location += offset;
        
        NSString* match = [regex replacementStringForResult:result
                                                   inString:mutableString
                                                     offset:offset
                                                   template:@"$0"];

        NSString* replacement = block(match);
        
        // make the replacement
        [mutableString replaceCharactersInRange:resultRange withString:replacement];
        
        // update the offset based on the replacement
        offset += ([replacement length] - resultRange.length);
    }
    return mutableString;
}

@end

@implementation TransitProxy {
    NSString* _proxyId;
    __weak TransitContext* _rootContext;
}

-(id)initWithRootContext:(TransitContext*)rootContext proxyId:(NSString*)proxyId {
    self = [self init];
    if(self) {
        _rootContext = rootContext;
        _proxyId = proxyId;
    }
    return self;
}

-(id)initWithRootContext:(TransitContext*)rootContext value:(id)value {
    self = [self init];
    if(self){
        _rootContext = rootContext;
        _value = value;
    }
    return self;
}

-(id)initWithRootContext:(TransitContext *)rootContext jsRepresentation:(NSString*)jsRepresentation {
    return [self initWithRootContext:rootContext value:[TransitJSDirectExpression expression:jsRepresentation]];
}


-(id)initWithRootContext:(TransitContext*)rootContext {
    return [self initWithRootContext:rootContext proxyId:nil];
}

-(void)dealloc {
    [self dispose];
}

-(BOOL)disposed {
    return _rootContext == nil;
}

-(void)clearRootContextAndProxyId {
    _rootContext = nil;
    _proxyId = nil;
}

-(void)dispose {
    if(_rootContext) {
        if(_proxyId){
            [_rootContext releaseJSProxyWithId: _proxyId];
        }
        [self clearRootContextAndProxyId];
    }
}

-(NSString*)proxyId {
    return _proxyId;
}

-(TransitContext*)rootContext{
    return _rootContext;
}

-(id)eval:(NSString*)jsCode {
    return [self eval:jsCode thisArg:self arguments:@[]];
}

-(id)eval:(NSString*)jsCode arguments:(NSArray*)arguments {
    return [self eval:jsCode thisArg:self arguments:arguments];
}

-(id)eval:(NSString*)jsCode thisArg:(id)thisArg arguments:(NSArray*)arguments {
    return [_rootContext eval:jsCode thisArg:thisArg arguments:arguments];
}

-(NSString*)jsRepresentation {
    if(_proxyId && _rootContext)
       return [_rootContext jsRepresentationForProxyWithId:_proxyId];
    
    if(_value) {
        if([_value respondsToSelector:@selector(jsRepresentation)])
            return [_value jsRepresentation];
        else
            return [self.class jsRepresentation:_value];
    }
    
    return [self.class jsRepresentation:self];
}

-(id)transitGlobalVarProxy {
    NSAssert(_rootContext, @"rootcontext not set");
    return _rootContext.transitGlobalVarProxy;
}

+(NSString*)jsRepresentation:(id)object {
    SBJsonWriter* writer = [SBJsonWriter new];
    NSString* json = [writer stringWithObject: @[object]];
    if(json == nil)
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"cannot be represented as JSON: %@", object] userInfo:nil];

    return [json substringWithRange:NSMakeRange(1, json.length-2)];
}

+(NSString*)jsExpressionFromCode:(NSString*)jsCode arguments:(NSArray*)arguments {
    NSError* error;
    NSRegularExpression *regex = [NSRegularExpression
                                  regularExpressionWithPattern:@"@"
                                  options:0
                                  error:&error];
    
    NSMutableArray* mutableArguments = [arguments mutableCopy];
    jsCode = [jsCode stringByReplacingMatchesOf:regex withTransformation:^(NSString* match){
        if(mutableArguments.count <=0)
            @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"too few arguments" userInfo:nil];
        
        id elem = mutableArguments[0];
        NSString* jsRepresentation = [elem respondsToSelector:@selector(jsRepresentation)] ? [elem performSelector:@selector(jsRepresentation)] : [self jsRepresentation:elem];
        NSString* result =  [NSString stringWithFormat:@"%@", jsRepresentation];
        
        [mutableArguments removeObjectAtIndex:0];
        return result;
    }];
    
    if(mutableArguments.count >0)
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"too many arguments" userInfo:nil];
    
    return jsCode;
}

@end

NSUInteger _TRANSIT_CONTEXT_LIVING_INSTANCE_COUNT = 0;

@implementation TransitContext {
    NSMutableDictionary* _retainedNativeProxies;
}

-(id)init {
    self = [super init];
    if(self){
        _TRANSIT_CONTEXT_LIVING_INSTANCE_COUNT++;
        _retainedNativeProxies = [NSMutableDictionary dictionary];
    }
    return self;
}

-(void)dealloc {
    // dispose manually from here to maintain correct life cycle
    [self disposeAllNativeProxies];
    _TRANSIT_CONTEXT_LIVING_INSTANCE_COUNT--;
}

-(void)dispose {
    [self disposeAllNativeProxies];
}

-(NSString*)jsRepresentationForProxyWithId:(NSString*)proxyId {
    return [TransitProxy jsExpressionFromCode:@"@.retained[@]" arguments:@[self.transitGlobalVarProxy, proxyId]];
}

-(void)disposeAllNativeProxies {
    for (id proxy in _retainedNativeProxies.allValues) {
        [proxy dispose];
    }
}

-(void)releaseJSProxyWithId:(NSString*)id {
    @throw @"not implemented, yet";
}

-(void)retainNativeProxy:(TransitProxy*)proxy {
    NSParameterAssert(proxy.rootContext == self);
    NSParameterAssert(proxy.proxyId);
    
//    if(_retainedNativeProxies[proxy.proxyId])
//        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"cannot retain native proxy twice" userInfo:nil];
    
    _retainedNativeProxies[proxy.proxyId] = proxy;
}

-(void)releaseNativeProxy:(TransitProxy *)proxy {
    NSParameterAssert(proxy.rootContext == self);
    NSParameterAssert(proxy.proxyId);
    
//    id existing = _retainedNativeProxies[proxy.proxyId];
//    if(!existing)
//        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"cannot release unretained proxy" userInfo:nil];

    [_retainedNativeProxies removeObjectForKey:proxy.proxyId];
}

-(NSDictionary*)retainedNativeProxies {
    return _retainedNativeProxies;
}

-(id)transitGlobalVarProxy {
    return [TransitJSDirectExpression expression:@"transit"];
}

@end

@implementation TransitUIWebViewContext{
    void(^_handleRequestBlock)(TransitUIWebViewContext*,NSURLRequest*);
}

-(void)setHandleRequestBlock:(void (^)(TransitUIWebViewContext*,NSURLRequest*))testCallBlock {
    _handleRequestBlock = [testCallBlock copy];
}

-(void (^)(TransitUIWebViewContext*,NSURLRequest*))handleRequestBlock {
    return _handleRequestBlock;
}

NSString* _TRANSIT_SCHEME = @"transit";
NSString* _TRANSIT_URL_TESTPATH = @"testcall";

+(id)contextWithUIWebView:(UIWebView*)webView {
    return [[self alloc] initWithUIWebView: webView];
}

-(id)initWithUIWebView:(UIWebView*)webView {
    self = [self init];
    if(self) {
        _webView = webView;
        [self bindToWebView];
    }
    return self;
}

-(void)bindToWebView {
    _webView.delegate = self;
    if(!_webView.loading)
        [self eval:_TRANSIT_JS_RUNTIME_CODE];
}

-(id)eval:(NSString *)jsCode thisArg:(id)thisArg arguments:(NSArray *)arguments {
    SBJsonParser *parser = [SBJsonParser new];
    NSString* jsExpression = [self.class jsExpressionFromCode:jsCode arguments:arguments];
    id adjustedThisArg = thisArg == self ? nil : thisArg;
    NSString* jsAdjustedThisArg = adjustedThisArg ? [TransitProxy jsRepresentation:thisArg] : @"null";
    NSString* jsApplyExpression = [NSString stringWithFormat:@"function(){return %@;}.call(%@)", jsExpression, jsAdjustedThisArg];
    NSString* js = [NSString stringWithFormat: @"JSON.stringify({v: %@})", jsApplyExpression];
    NSString* jsResult = [_webView stringByEvaluatingJavaScriptFromString: js];
    return [parser objectWithString:jsResult][@"v"];
}

#pragma UIWebViewDelegate

-(BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
    if([request.URL.scheme isEqual:_TRANSIT_SCHEME]){
        if(self.handleRequestBlock)
            self.handleRequestBlock(self, request);
            
        return NO;
    }
    return YES;
}

@end

@implementation TransitFunction

-(id)call {
    return [self callWithThisArg:nil arguments:@[]];
}

-(id)callWithArguments:(NSArray*)arguments {
    return [self callWithThisArg:nil arguments:arguments];
}

-(id)callWithThisArg:(id)thisArg arguments:(NSArray*)arguments {
    @throw @"must be implemented by subclass";
}

@end

@implementation TransitNativeFunction

-(id)initWithRootContext:(TransitContext *)rootContext nativeId:(NSString*)nativeId block:(TransitFunctionBlock)block {
    self = [self initWithRootContext:rootContext];
    if(self) {
        NSParameterAssert(nativeId);
        NSParameterAssert(block);
        _nativeId = nativeId;
        _block = block;
    }
    return self;
}

-(id)callWithThisArg:(id)thisArg arguments:(NSArray*)arguments {
    return _block(thisArg, arguments);
}

-(NSString*)jsRepresentation {
    return [TransitProxy jsExpressionFromCode:@"@.nativeFunction(@)" arguments:@[self.transitGlobalVarProxy, _nativeId]];
}

-(void)dispose {
    if(self.rootContext) {
        if(self.proxyId)
            [self.rootContext releaseNativeProxy:self];
        [self clearRootContextAndProxyId];
    }
}

@end


@implementation TransitJSFunction

-(id)callWithThisArg:(id)thisArg arguments:(NSArray *)arguments {
    if(self.disposed)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"function already disposed" userInfo:nil];
    
    NSMutableArray *argumentsPlaceholder = [NSMutableArray array];
    while(argumentsPlaceholder.count<arguments.count)
          [argumentsPlaceholder addObject:@"@"];
    
    NSString* js = [NSString stringWithFormat:@"%@(%@)", self.jsRepresentation, [argumentsPlaceholder componentsJoinedByString:@","]];
    return [self.rootContext eval:js thisArg:thisArg arguments:arguments];
}

@end

// NOTE: this value is automatically generated by grunt. DO NOT CHANGE ANYTHING BEHIND THIS LINE
NSString* _TRANSIT_JS_RUNTIME_CODE = @
    // _TRANSIT_JS_RUNTIME_CODE_START
    "(function(){/*global Document Element */\n\n(function(globalName){\n    var transit = {\n        retained:{},\n        lastRetainId: 0\n    };\n\n    var PREFIX_MAGIC_FUNCTION = \"__TRANSIT_JS_FUNCTION_\";\n    var PREFIX_MAGIC_NATIVE_FUNCTION = \"__TRANSIT_NATIVE_FUNCTION_\";\n    var PREFIX_MAGIC_OBJECT = \"__TRANSIT_OBJECT_PROXY_\";\n\n    var GLOBAL_OBJECT = window;\n\n    transit.doInvokeNative = function(invocationDescription){\n        throw \"must be replaced by native runtime \" + invocationDescription;\n    };\n\n    transit.nativeFunction = function(nativeId){\n        var f = function(){\n            transit.invokeNative(nativeId, this, arguments);\n        };\n        f.transitNativeId = PREFIX_MAGIC_NATIVE_FUNCTION + nativeId;\n        return f;\n    };\n\n    transit.recursivelyProxifyMissingFunctionProperties = function(missing, existing) {\n        for(var key in existing) {\n            if(existing.hasOwnProperty(key)) {\n                var existingValue = existing[key];\n\n                if(typeof existingValue === \"function\") {\n                    missing[key] = transit.proxify(existingValue);\n                }\n                if(typeof existingValue === \"object\" && typeof missing[key] === \"object\" && missing[key] !== null) {\n                    transit.recursivelyProxifyMissingFunctionProperties(missing[key], existingValue);\n                }\n            }\n        }\n    };\n\n    transit.proxify = function(elem) {\n        if(typeof elem === \"function\") {\n            if(typeof elem.transitNativeId !== \"undefined\") {\n                return elem.transitNativeId;\n            } else {\n                return transit.retainElement(elem);\n            }\n        }\n\n        if(typeof elem === \"object\") {\n            if(elem instanceof Document || elem instanceof Element) {\n                return transit.retainElement(elem);\n            }\n\n            var copy;\n            try {\n                copy = JSON.parse(JSON.stringify(elem));\n            } catch (e) {\n                return transit.retainElement(elem);\n            }\n            transit.recursivelyProxifyMissingFunctionProperties(copy, elem);\n            return copy;\n        }\n\n        return elem;\n    };\n\n    transit.invokeNative = function(nativeId, thisArg, args) {\n        var invocationDescription = {\n            nativeId: nativeId,\n            thisArg: (thisArg === GLOBAL_OBJECT) ? null : transit.proxify(thisArg),\n            args: []\n        };\n\n        for(var i = 0;i<args.length; i++) {\n            invocationDescription.args.push(transit.proxify(args[i]));\n        }\n\n        return transit.doInvokeNative(invocationDescription);\n    };\n\n    transit.retainElement = function(element){\n        transit.lastRetainId++;\n        var id = \"\" + transit.lastRetainId;\n        if(typeof element === \"object\") {\n            id = PREFIX_MAGIC_OBJECT + id;\n        }\n        if(typeof element === \"function\") {\n            id = PREFIX_MAGIC_FUNCTION + id;\n        }\n\n        transit.retained[id] = element;\n        return id;\n    };\n\n    transit.releaseElementWithId = function(retainId) {\n        if(typeof transit.retained[retainId] === \"undefined\") {\n            throw \"no retained element with Id \" + retainId;\n        }\n\n        delete transit.retained[retainId];\n    };\n\n    window[globalName] = transit;\n\n})(\"transit\");(function(globalName){\n    var transit = window[globalName];\n\n    var callCount = 0;\n    transit.doInvokeNative = function(invocationDescription){\n        invocationDescription.callNumber = ++callCount;\n        transit.nativeInvokeTransferObject = invocationDescription;\n\n        var iFrame = document.createElement('iframe');\n        iFrame.setAttribute('src', 'transit:'+callCount);\n\n        /* this call blocks until native code returns */\n        /* native ccde reads from and writes to transit.nativeInvokeTransferObject */\n        document.documentElement.appendChild(iFrame);\n\n        /* free resources */\n        iFrame.parentNode.removeChild(iFrame);\n        iFrame = null;\n\n        return transit.nativeInvokeTransferObject;\n    };\n\n})(\"transit\");})()"
    // _TRANSIT_JS_RUNTIME_CODE_END
    ;