#import "CodePush.h"
#import <UIKit/UIKit.h>

@implementation CodePushConfig {
    NSMutableDictionary *_configDictionary;
}

static CodePushConfig *_currentConfig;

static NSString * const AppVersionConfigKey = @"appVersion";
static NSString * const BuildVersionConfigKey = @"buildVersion";
static NSString * const ClientUniqueIDConfigKey = @"clientUniqueId";
static NSString * const DeploymentKeyConfigKey = @"deploymentKey";
static NSString * const ServerURLConfigKey = @"serverUrl";
static NSString * const PublicKeyKey = @"publicKey";
// 读取 Info.plist 中配置的多 bundle namespaces
static NSString * const MultiBundlesKey = @"multiBundles";
// 当前多 bundle 的 HEAD 指针
static NSString * const MultiBundlesHeadKey = @"CODE_PUSH_MULTI_BUNDLES_HEAD";

+ (instancetype)current
{
    return _currentConfig;
}

+ (void)initialize
{
    if (self == [CodePushConfig class]) {
        _currentConfig = [[CodePushConfig alloc] init];
    }
}

- (instancetype)init
{
    self = [super init];
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];

    NSString *appVersion = [infoDictionary objectForKey:@"CFBundleShortVersionString"];
    NSString *buildVersion = [infoDictionary objectForKey:(NSString *)kCFBundleVersionKey];
    NSString *deploymentKey = [infoDictionary objectForKey:@"CodePushDeploymentKey"];
    NSString *serverURL = [infoDictionary objectForKey:@"CodePushServerURL"];
    NSString *publicKey = [infoDictionary objectForKey:@"CodePushPublicKey"];
    NSArray<NSDictionary<NSString *, NSString *> *> *multiBundles = [infoDictionary objectForKey:@"CodePushMultiBundles"];
    
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSString *clientUniqueId = [userDefaults stringForKey:ClientUniqueIDConfigKey];
    NSString *multiBundlesHead = [userDefaults stringForKey:MultiBundlesHeadKey];
    
    if (clientUniqueId == nil) {
        clientUniqueId = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
        [userDefaults setObject:clientUniqueId forKey:ClientUniqueIDConfigKey];
        [userDefaults synchronize];
    }
    // 如果配置了多 bundle，但当前preferences内无 head，将 head 默认指向第一个内置 bundle
    if (multiBundlesHead == nil && multiBundles != nil && multiBundles.count > 0) {
        multiBundlesHead = multiBundles[0][@"bundle"];
        [userDefaults setObject:multiBundlesHead forKey:MultiBundlesHeadKey];
        [userDefaults synchronize];
    }

    if (!serverURL) {
        serverURL = @"https://codepush.appcenter.ms/";
    }

    _configDictionary = [NSMutableDictionary dictionary];

    if (appVersion) [_configDictionary setObject:appVersion forKey:AppVersionConfigKey];
    if (buildVersion) [_configDictionary setObject:buildVersion forKey:BuildVersionConfigKey];
    if (serverURL) [_configDictionary setObject:serverURL forKey:ServerURLConfigKey];
    if (clientUniqueId) [_configDictionary setObject:clientUniqueId forKey:ClientUniqueIDConfigKey];
    if (deploymentKey) [_configDictionary setObject:deploymentKey forKey:DeploymentKeyConfigKey];
    if (publicKey) [_configDictionary setObject:publicKey forKey:PublicKeyKey];
    if (multiBundles) [_configDictionary setObject:multiBundles forKey:MultiBundlesKey];
    if (multiBundlesHead) [_configDictionary setObject:multiBundlesHead forKey:MultiBundlesHeadKey];

    CPLog(@"---> %@", _configDictionary);
    return self;
}

- (NSString *)appVersion
{
    return [_configDictionary objectForKey:AppVersionConfigKey];
}

- (NSString *)buildVersion
{
    return [_configDictionary objectForKey:BuildVersionConfigKey];
}

- (NSDictionary *)configuration
{
    return _configDictionary;
}

- (NSString *)deploymentKey
{
    if (self.isMultiBundleMode) {
        int found = -1;
        for (int i = 0; i < [self.multiBundles count]; i++) {
            NSString *bundle = self.multiBundles[i][@"bundle"];
            if ([bundle isEqualToString:self.multiBundlesHead]) {
                found = i;
                break;
            }
        }
        if (found == -1) return [_configDictionary objectForKey:DeploymentKeyConfigKey];
        return self.multiBundles[found][@"deploymentKey"];
    }
    return [_configDictionary objectForKey:DeploymentKeyConfigKey];
}

- (NSString *)serverURL
{
    return [_configDictionary objectForKey:ServerURLConfigKey];
}

- (NSString *)clientUniqueId
{
    return [_configDictionary objectForKey:ClientUniqueIDConfigKey];
}

- (NSString *)publicKey
{
    return [_configDictionary objectForKey:PublicKeyKey];
}

// multiBundles getter
- (NSDictionary<NSString *, NSString *> *) multiBundles
{
    return [_configDictionary objectForKey:MultiBundlesKey];
}

// multiBundlesHead getter
- (NSString *) multiBundlesHead
{
    return [_configDictionary objectForKey:MultiBundlesHeadKey];
}

// 是否多 bundle 模式
- (BOOL) isMultiBundleMode
{
    return [self multiBundles] != nil && [[self multiBundles] count] > 0;
}

// multiBundlesHead setter
- (void)setMultiBundlesHead:(NSString *)multiBundlesHead
{
    // 非多bundle模式下，quick returns
    if (!self.isMultiBundleMode) {
        CPLog(@"非多 bundle 模式下，CodePushConfig.setMultiBundlesHead 失效!");
        return;
    }
    
    // 写入内存
    [_configDictionary setValue:multiBundlesHead forKey:MultiBundlesHeadKey];
    // 同时持久化
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setObject:multiBundlesHead forKey:MultiBundlesHeadKey];
    [userDefaults synchronize];
}

// 读取 binary bundle 时，subdir 需根据当前是否多 bundle 模式来定
- (NSString *) bundleResourceSubdirectory:(NSString *)subdirectory
{
    if (!self.isMultiBundleMode) return subdirectory;
    
    return [@"" stringByAppendingFormat:@"/%@/%@", @"bundles", self.multiBundlesHead];
}

// 读取 CodePush path 时，根据多 bundle 模式，拼接各 bundle 的目录
- (NSString *) getCodePushPath:(NSString *) codePushPath
{
    if (!self.isMultiBundleMode) return codePushPath;
    
    return [[CodePush getApplicationSupportDirectory] stringByAppendingFormat:@"/CodePush/%@", self.multiBundlesHead];
}

// 读写 preferences 时，根据多 bundle 模式，加多一个后缀进行隔离
- (id)preferenceObjectForKey:(NSString *)key
{
    NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
    NSString* normalizedKey = self.isMultiBundleMode ? [key stringByAppendingString:self.multiBundlesHead] : key;
    return [preferences objectForKey:normalizedKey];
}

- (void)preferenceSetObject:(id)obj forKey:(NSString *)key
{
    NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
    NSString* normalizedKey = self.isMultiBundleMode ? [key stringByAppendingString:self.multiBundlesHead] : key;
    [preferences setObject:obj forKey:normalizedKey];
    [preferences synchronize];
}

- (void) preferenceRemoveObjectForKey:(NSString *)key
{
    NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
    [preferences removeObjectForKey:key];
    [preferences synchronize];
}
// 切换内置 bundle
- (BOOL)switchBundle:(NSString *)head
{
    if (head == nil) return NO;
    if (!self.isMultiBundleMode) return NO;
    
    int found = -1;
    for (int i = 0; i < [self.multiBundles count]; i++) {
        NSString *bundle = self.multiBundles[i][@"bundle"];
        if ([bundle isEqualToString:self.multiBundlesHead]) {
            found = i;
            break;
        }
    }
    if (found == -1) return NO;
    if ([self.multiBundlesHead isEqualToString:head]) return NO;

    [self setMultiBundlesHead:head];
    return YES;
}

- (void)setAppVersion:(NSString *)appVersion
{
    [_configDictionary setValue:appVersion forKey:AppVersionConfigKey];
}

- (void)setDeploymentKey:(NSString *)deploymentKey
{
    [_configDictionary setValue:deploymentKey forKey:DeploymentKeyConfigKey];
}

- (void)setServerURL:(NSString *)serverURL
{
    [_configDictionary setValue:serverURL forKey:ServerURLConfigKey];
}

//no setter for PublicKey, because it's need to be hard coded within Info.plist for safety

@end
