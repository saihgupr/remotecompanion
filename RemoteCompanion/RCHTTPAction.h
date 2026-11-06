#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The REST API Call action: one HTTP request, stored as
//   http-request {"method":"POST","url":"https://example.com/hook","headers":{…},"body":"…"}
@interface RCHTTPAction : NSObject

+ (NSString *)actionStringWithMethod:(NSString *)method
                                 url:(NSString *)url
                             headers:(NSDictionary<NSString *, NSString *> *)headers
                                body:(NSString *)body;

// The parts of an action, or nil when it isn't a valid http-request action.
// Keys: method (NSString), url (NSString), headers (NSDictionary), body (NSString)
+ (nullable NSDictionary *)componentsFromActionString:(nullable NSString *)action;

// Header lines as the editor shows them: one "Name: Value" per line. A line without a colon
// is returned as invalidLine so the editor can point at it. Values are trimmed.
+ (nullable NSDictionary<NSString *, NSString *> *)headersFromLines:(NSString *)text
                                                        invalidLine:(NSString *_Nullable *_Nullable)invalidLine;
+ (NSString *)linesFromHeaders:(nullable NSDictionary<NSString *, NSString *> *)headers;

@end

NS_ASSUME_NONNULL_END
