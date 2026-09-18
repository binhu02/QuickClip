#import <Foundation/Foundation.h>
#import <ServiceManagement/ServiceManagement.h>

NS_ASSUME_NONNULL_BEGIN

@interface LoginItemManager : NSObject

@property (nonatomic, readonly) BOOL isEnabled;
@property (nonatomic, readonly) SMAppServiceStatus status;

- (BOOL)setEnabled:(BOOL)enabled error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
