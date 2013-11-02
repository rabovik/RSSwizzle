//
//  RSSwizzleTests.m
//  RSSwizzleTests
//
//  Created by Yan Rabovik on 05.09.13.
//
//

#import <SenTestingKit/SenTestingKit.h>
#import "RSTestsLog.h"
#import "RSSwizzle.h"
#import <objc/runtime.h>

#pragma mark - HELPER CLASSES -

@interface RSSwizzleTestClass_A : NSObject @end
@implementation RSSwizzleTestClass_A
-(int)calc:(int)num{ return num; }
-(BOOL)methodReturningBOOL{ return YES; };
-(void)methodWithArgument:(id)arg{};
-(void)methodForAlwaysSwizzling{};
-(void)methodForSwizzlingOncePerClass{};
-(void)methodForSwizzlingOncePerClassOrSuperClasses{};
-(NSString *)string{ return @"ABC"; }
+(NSNumber *)sumFloat:(float)floatSummand withDouble:(double)doubleSummand{
    return @(floatSummand + doubleSummand);
}
@end

@interface RSSwizzleTestClass_B : RSSwizzleTestClass_A @end
@implementation RSSwizzleTestClass_B @end

@interface RSSwizzleTestClass_C : RSSwizzleTestClass_B @end
@implementation RSSwizzleTestClass_C
-(void)dealloc{ RSTestsLog(@"C-"); };
-(int)calc:(int)num{ return [super calc:num] * 3; }
@end

@interface RSSwizzleTestClass_D : RSSwizzleTestClass_C @end
@implementation RSSwizzleTestClass_D @end

@interface RSSwizzleTestClass_D2 : RSSwizzleTestClass_C @end
@implementation RSSwizzleTestClass_D2 @end

#pragma mark - HELPER FUNCTIONS -

static void swizzleVoidMethod(Class classToSwizzle,
                              SEL selector,
                              dispatch_block_t blockBefore,
                              RSSwizzleMode mode,
                              const void *key)
{
    RSSwizzleInstanceMethod(classToSwizzle,
                            selector,
                            RSSWReturnType(void),
                            RSSWArguments(),
                            RSSWReplacement(
    {
        blockBefore();
        RSSWCallOriginal();
    }), mode, key);
}

static void swizzleDealloc(Class classToSwizzle, dispatch_block_t blockBefore){
    SEL selector = NSSelectorFromString(@"dealloc");
    swizzleVoidMethod(classToSwizzle, selector, blockBefore, RSSwizzleModeAlways, NULL);
}

static void swizzleNumber(Class classToSwizzle, int(^transformationBlock)(int)){
    RSSwizzleInstanceMethod(classToSwizzle,
                            @selector(calc:),
                            RSSWReturnType(int),
                            RSSWArguments(int num),
                            RSSWReplacement(
    {
        int res = RSSWCallOriginal(num);
        return transformationBlock(res);
    }), RSSwizzleModeAlways, NULL);
}

#pragma mark - TESTS -

@interface RSSwizzleTests : SenTestCase @end

@implementation RSSwizzleTests

#pragma mark - Setup

+(void)setUp{
    [self swizzleDeallocs];
    [self swizzleCalc];
}

-(void)setUp{
    [super setUp];
    CLEAR_LOG();
}

#pragma mark - Dealloc Swizzling

+(void)swizzleDeallocs{
    // 1) Swizzling a class that does not implement the method...
    swizzleDealloc([RSSwizzleTestClass_D class], ^{
        RSTestsLog(@"d-");
    });
    // ...should not break swizzling of its superclass.
    swizzleDealloc([RSSwizzleTestClass_C class], ^{
        RSTestsLog(@"c-");
    });
    // 2) Swizzling a class that does not implement the method
    // should not affect classes with the same superclass.
    swizzleDealloc([RSSwizzleTestClass_D2 class], ^{
        RSTestsLog(@"d2-");
    });
    
    // 3) We should be able to swizzle classes several times...
    swizzleDealloc([RSSwizzleTestClass_D class], ^{
        RSTestsLog(@"d'-");
    });
    // ...and nothing should be breaked up.
    swizzleDealloc([RSSwizzleTestClass_C class], ^{
        RSTestsLog(@"c'-");
    });
    
    // 4) Swizzling a class inherited from NSObject and does not
    // implementing the method.
    swizzleDealloc([RSSwizzleTestClass_A class], ^{
        RSTestsLog(@"a");
    });
}

-(void)testDeallocSwizzling
{
    @autoreleasepool {
        id object = [RSSwizzleTestClass_D new];
        object = nil;
    }
    ASSERT_LOG_IS(@"d'-d-c'-c-C-a");
}

#pragma mark - Calc: Swizzling

+(void)swizzleCalc{
    
    swizzleNumber([RSSwizzleTestClass_C class], ^int(int num){
        return num + 17;
    });
    
    swizzleNumber([RSSwizzleTestClass_D class], ^int(int num){
        return num * 11;
    });
    swizzleNumber([RSSwizzleTestClass_C class], ^int(int num){
        return num * 5;
    });
    swizzleNumber([RSSwizzleTestClass_D class], ^int(int num){
        return num - 20;
    });
    
    swizzleNumber([RSSwizzleTestClass_A class], ^int(int num){
        return num * -1;
    });
}

-(void)testCalcSwizzling
{
    RSSwizzleTestClass_D *object = [RSSwizzleTestClass_D new];
    int res = [object calc:2];
    STAssertTrue(res == ((2 * (-1) * 3) + 17) * 5 * 11 - 20, @"%d",res);
}

#pragma mark - String Swizzling
-(void)testStringSwizzling{
    SEL selector = @selector(string);
    RSSwizzleTestClass_A *a = [RSSwizzleTestClass_A new];
    
    RSSwizzleInstanceMethod([a class],
                            selector,
                            RSSWReturnType(NSString *),
                            RSSWArguments(),
                            RSSWReplacement(
    {
        NSString *res = RSSWCallOriginal();
        return [res stringByAppendingString:@"DEF"];
    }), RSSwizzleModeAlways, NULL);
    
    STAssertTrue([[a string] isEqualToString:@"ABCDEF"], nil);
}

#pragma mark - Class Swizzling
-(void)testClassSwizzling{
    RSSwizzleClassMethod([RSSwizzleTestClass_B class],
                         @selector(sumFloat:withDouble:),
                         RSSWReturnType(NSNumber *),
                         RSSWArguments(float floatSummand, double doubleSummand),
                         RSSWReplacement(
    {
        NSNumber *result = RSSWCallOriginal(floatSummand, doubleSummand);
        return @([result doubleValue]* 2.);
    }));
    
    STAssertEqualObjects(@(2.), [RSSwizzleTestClass_A sumFloat:0.5 withDouble:1.5 ], nil);
    STAssertEqualObjects(@(4.), [RSSwizzleTestClass_B sumFloat:0.5 withDouble:1.5 ], nil);
    STAssertEqualObjects(@(4.), [RSSwizzleTestClass_C sumFloat:0.5 withDouble:1.5 ], nil);
}

#pragma mark - Test Assertions
#if !defined(NS_BLOCK_ASSERTIONS)
-(void)testThrowsOnSwizzlingNonexistentMethod{
    SEL selector = NSSelectorFromString(@"nonexistent");
    RSSwizzleImpFactoryBlock factoryBlock = ^id(RSSwizzleInfo *swizzleInfo){
        return ^(__unsafe_unretained id self){
            void (*originalIMP)(__unsafe_unretained id, SEL);
            originalIMP = (__typeof(originalIMP))[swizzleInfo getOriginalImplementation];
            originalIMP(self,selector);
        };
    };
    STAssertThrows([RSSwizzle
                    swizzleInstanceMethod:selector
                    inClass:[RSSwizzleTestClass_A class]
                    newImpFactory:factoryBlock
                    mode:RSSwizzleModeAlways
                    key:NULL], nil);
}

-(void)testThrowsOnSwizzlingWithIncorrectImpType{
    // Different return types
    RSSwizzleImpFactoryBlock voidNoArgFactory =
        ^id(RSSwizzleInfo *swizzleInfo)
    {
        return ^(__unsafe_unretained id self){};
    };
    STAssertThrows([RSSwizzle
                    swizzleInstanceMethod:@selector(methodReturningBOOL)
                    inClass:[RSSwizzleTestClass_A class]
                    newImpFactory:voidNoArgFactory
                    mode:RSSwizzleModeAlways
                    key:NULL], nil);
    // Different arguments count
    STAssertThrows([RSSwizzle
                    swizzleInstanceMethod:@selector(methodWithArgument:)
                    inClass:[RSSwizzleTestClass_A class]
                    newImpFactory:voidNoArgFactory
                    mode:RSSwizzleModeAlways
                    key:NULL], nil);
    // Different arguments type
    RSSwizzleImpFactoryBlock voidIntArgFactory =
    ^id(RSSwizzleInfo *swizzleInfo)
    {
        return ^int(__unsafe_unretained id self){ return 0; };
    };
    STAssertThrows([RSSwizzle
                    swizzleInstanceMethod:@selector(methodWithArgument:)
                    inClass:[RSSwizzleTestClass_A class]
                    newImpFactory:voidIntArgFactory
                    mode:RSSwizzleModeAlways
                    key:NULL], nil);
}

-(void)testThrowsOnPassingIncorrectImpFactory{
    STAssertThrows([RSSwizzle
                    swizzleInstanceMethod:@selector(methodWithArgument:)
                    inClass:[RSSwizzleTestClass_A class]
                    newImpFactory:^id(id x){ return nil; }
                    mode:RSSwizzleModeAlways
                    key:NULL], nil);
}
#endif

#pragma mark - Mode tests

-(void)testAlwaysSwizzlingMode{
    for (int i = 3; i > 0; --i) {
        swizzleVoidMethod([RSSwizzleTestClass_A class],
                          @selector(methodForAlwaysSwizzling), ^{
                              RSTestsLog(@"A");
                          },
                          RSSwizzleModeAlways,
                          NULL);
        swizzleVoidMethod([RSSwizzleTestClass_B class],
                          @selector(methodForAlwaysSwizzling), ^{
                              RSTestsLog(@"B");
                          },
                          RSSwizzleModeAlways,
                          NULL);
    }

    RSSwizzleTestClass_B *object = [RSSwizzleTestClass_B new];
    [object methodForAlwaysSwizzling];
    ASSERT_LOG_IS(@"BBBAAA");
}

-(void)testSwizzleOncePerClassMode{
    static void *key = &key;
    for (int i = 3; i > 0; --i) {
        swizzleVoidMethod([RSSwizzleTestClass_A class],
                          @selector(methodForSwizzlingOncePerClass), ^{
                              RSTestsLog(@"A");
                          },
                          RSSwizzleModeOncePerClass,
                          key);
        swizzleVoidMethod([RSSwizzleTestClass_B class],
                          @selector(methodForSwizzlingOncePerClass), ^{
                              RSTestsLog(@"B");
                          },
                          RSSwizzleModeOncePerClass,
                          key);
    }
    RSSwizzleTestClass_B *object = [RSSwizzleTestClass_B new];
    [object methodForSwizzlingOncePerClass];
    ASSERT_LOG_IS(@"BA");
}

-(void)testSwizzleOncePerClassOrSuperClassesMode{
    static void *key = &key;
    for (int i = 3; i > 0; --i) {
        swizzleVoidMethod([RSSwizzleTestClass_A class],
                          @selector(methodForSwizzlingOncePerClassOrSuperClasses), ^{
                              RSTestsLog(@"A");
                          },
                          RSSwizzleModeOncePerClassAndSuperclasses,
                          key);
        swizzleVoidMethod([RSSwizzleTestClass_B class],
                          @selector(methodForSwizzlingOncePerClassOrSuperClasses), ^{
                              RSTestsLog(@"B");
                          },
                          RSSwizzleModeOncePerClassAndSuperclasses,
                          key);
    }
    RSSwizzleTestClass_B *object = [RSSwizzleTestClass_B new];
    [object methodForSwizzlingOncePerClassOrSuperClasses];
    ASSERT_LOG_IS(@"A");
}

@end
