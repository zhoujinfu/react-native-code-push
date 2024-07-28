#import "CodePush.h"

static NSString *const AppVersionKey = @"appVersion";
static NSString *const DeploymentFailed = @"DeploymentFailed";
static NSString *const DeploymentKeyKey = @"deploymentKey";
static NSString *const DeploymentSucceeded = @"DeploymentSucceeded";
static NSString *const LabelKey = @"label";
static NSString *const LastDeploymentReportKey = @"CODE_PUSH_LAST_DEPLOYMENT_REPORT";
static NSString *const PackageKey = @"package";
static NSString *const PreviousDeploymentKeyKey = @"previousDeploymentKey";
static NSString *const PreviousLabelOrAppVersionKey = @"previousLabelOrAppVersion";
static NSString *const RetryDeploymentReportKey = @"CODE_PUSH_RETRY_DEPLOYMENT_REPORT";
static NSString *const StatusKey = @"status";

@implementation CodePushTelemetryManager

+ (NSDictionary *)getBinaryUpdateReport:(NSString *)appVersion
{
    NSString *previousStatusReportIdentifier = [self getPreviousStatusReportIdentifier];
    if (previousStatusReportIdentifier == nil) {
        [self clearRetryStatusReport];
        return @{ AppVersionKey: appVersion };
    } else if (![previousStatusReportIdentifier isEqualToString:appVersion]) {
        if ([self isStatusReportIdentifierCodePushLabel:previousStatusReportIdentifier]) {
            NSString *previousDeploymentKey = [self getDeploymentKeyFromStatusReportIdentifier:previousStatusReportIdentifier];
            NSString *previousLabel = [self getVersionLabelFromStatusReportIdentifier:previousStatusReportIdentifier];
            [self clearRetryStatusReport];
            return @{
                      AppVersionKey: appVersion,
                      PreviousDeploymentKeyKey: previousDeploymentKey,
                      PreviousLabelOrAppVersionKey: previousLabel
                    };
        } else {
            [self clearRetryStatusReport];
            // Previous status report was with a binary app version.
            return @{
                      AppVersionKey: appVersion,
                      PreviousLabelOrAppVersionKey: previousStatusReportIdentifier
                    };
        }
    }

    return nil;
}

+ (NSDictionary *)getRetryStatusReport
{
    NSDictionary *retryStatusReport = [[CodePushConfig current] preferenceObjectForKey:RetryDeploymentReportKey];
    if (retryStatusReport) {
        [self clearRetryStatusReport];
        return retryStatusReport;
    } else {
        return nil;
    }
}

+ (NSDictionary *)getRollbackReport:(NSDictionary *)lastFailedPackage
{
    return @{
              PackageKey: lastFailedPackage,
              StatusKey: DeploymentFailed
            };
}

+ (NSDictionary *)getUpdateReport:(NSDictionary *)currentPackage
{
    NSString *currentPackageIdentifier = [self getPackageStatusReportIdentifier:currentPackage];
    NSString *previousStatusReportIdentifier = [self getPreviousStatusReportIdentifier];
    if (currentPackageIdentifier) {
        if (previousStatusReportIdentifier == nil) {
            [self clearRetryStatusReport];
            return @{
                      PackageKey: currentPackage,
                      StatusKey: DeploymentSucceeded
                    };
        } else if (![previousStatusReportIdentifier isEqualToString:currentPackageIdentifier]) {
            [self clearRetryStatusReport];
            if ([self isStatusReportIdentifierCodePushLabel:previousStatusReportIdentifier]) {
                NSString *previousDeploymentKey = [self getDeploymentKeyFromStatusReportIdentifier:previousStatusReportIdentifier];
                NSString *previousLabel = [self getVersionLabelFromStatusReportIdentifier:previousStatusReportIdentifier];
                return @{
                          PackageKey: currentPackage,
                          StatusKey: DeploymentSucceeded,
                          PreviousDeploymentKeyKey: previousDeploymentKey,
                          PreviousLabelOrAppVersionKey: previousLabel
                        };
            } else {
                // Previous status report was with a binary app version.
                return @{
                          PackageKey: currentPackage,
                          StatusKey: DeploymentSucceeded,
                          PreviousLabelOrAppVersionKey: previousStatusReportIdentifier
                        };
            }
        }
    }

    return nil;
}

+ (void)recordStatusReported:(NSDictionary *)statusReport
{
    // We don't need to record rollback reports, so exit early if that's what was specified.
    if ([DeploymentFailed isEqualToString:statusReport[StatusKey]]) {
        return;
    }
    
    if (statusReport[AppVersionKey]) {
        [self saveStatusReportedForIdentifier:statusReport[AppVersionKey]];
    } else if (statusReport[PackageKey]) {
        NSString *packageIdentifier = [self getPackageStatusReportIdentifier:statusReport[PackageKey]];
        [self saveStatusReportedForIdentifier:packageIdentifier];
    }
}

+ (void)saveStatusReportForRetry:(NSDictionary *)statusReport
{
    [[CodePushConfig current] preferenceSetObject:statusReport forKey:RetryDeploymentReportKey];
}

#pragma mark - private methods

+ (void)clearRetryStatusReport
{
    [[CodePushConfig current] preferenceSetObject:nil forKey:RetryDeploymentReportKey];
}

+ (NSString *)getDeploymentKeyFromStatusReportIdentifier:(NSString *)statusReportIdentifier
{
    return [[statusReportIdentifier componentsSeparatedByString:@":"] firstObject];
}

+ (NSString *)getPackageStatusReportIdentifier:(NSDictionary *)package
{
    // Because deploymentKeys can be dynamically switched, we use a
    // combination of the deploymentKey and label as the packageIdentifier.
    NSString *deploymentKey = [package objectForKey:DeploymentKeyKey];
    NSString *label = [package objectForKey:LabelKey];
    if (deploymentKey && label) {
        return [[deploymentKey stringByAppendingString:@":"] stringByAppendingString:label];
    } else {
        return nil;
    }
}

+ (NSString *)getPreviousStatusReportIdentifier
{
    NSString *sentStatusReportIdentifier = [[CodePushConfig current] preferenceObjectForKey:LastDeploymentReportKey];
    return sentStatusReportIdentifier;
}

+ (NSString *)getVersionLabelFromStatusReportIdentifier:(NSString *)statusReportIdentifier
{
    return [[statusReportIdentifier componentsSeparatedByString:@":"] lastObject];
}

+ (BOOL)isStatusReportIdentifierCodePushLabel:(NSString *)statusReportIdentifier
{
    return statusReportIdentifier != nil && [statusReportIdentifier rangeOfString:@":"].location != NSNotFound;
}

+ (void)saveStatusReportedForIdentifier:(NSString *)appVersionOrPackageIdentifier
{
    [[CodePushConfig current] preferenceSetObject:appVersionOrPackageIdentifier forKey:LastDeploymentReportKey];
}

@end
