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
                              const void *key) {
    [classToSwizzle swizzleInstanceMethod:selector usingFactory:^id (RSSWizzleImpProvider original, Class hookedClass, SEL selector) {
         return ^void(__unsafe_unretained id self){
             blockBefore();
             
             RSOriginalCast(void, original)(self, selector);
         };
     } mode:mode key:key];
}

static void swizzleDealloc(Class classToSwizzle, dispatch_block_t blockBefore){
    SEL selector = NSSelectorFromString(@"dealloc");
    swizzleVoidMethod(classToSwizzle, selector, blockBefore, RSSwizzleModeAlways, NULL);
}

static void swizzleNumber(Class classToSwizzle, int(^transformationBlock)(int)){
    SEL selector = NSSelectorFromString(@"calc:");
    [classToSwizzle swizzleInstanceMethod:selector usingFactory:^id (RSSWizzleImpProvider original, Class hookedClass, SEL selector) {
         return ^int(__unsafe_unretained id self, int num){
             int res = RSOriginalCast(int, original)(self,selector,num);
             
             return transformationBlock(res);
         };
     }];
}

#pragma mark - TESTS -

@interface RSSwizzleTests : SenTestCase @end

@implementation RSSwizzleTests

#pragma mark - Setup




+(void)setUp{
    //Super easy usage:
    [UIView swizzleInstanceMethod:@selector(alpha) usingFactory:^id (RSSWizzleImpProvider original, Class hookedClass, SEL selector) {
        return ^CGFloat (UIView *self) {
            CGFloat orig = RSOriginalCast(CGFloat, original)(self, selector);
            
            return orig+0.5f;
        };
    }];
    
    [UIView swizzleInstanceMethod:@selector(frame) usingFactory:^id (RSSWizzleImpProvider original, Class hookedClass, SEL selector) {
        return ^CGRect (UIView *self) {
            CGRect orig = RSOriginalCast(CGRect, original)(self, selector);
            
            orig.origin.x -= 5.0f;
            orig.origin.y += 5.0f;
            orig.size.width += +10.0f;
            orig.size.height += 50.0f;
            
            
            return orig;
        };
    }];
    
    UIView *v = [UIView new];
    
    
    NSLog(@"VIEW %@", v);

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

#pragma mark - Test Assertions
#if !defined(NS_BLOCK_ASSERTIONS)
-(void)testThrowsOnSwizzlingNonexistentMethod{
    SEL selector = NSSelectorFromString(@"nonexistent");
    RSSwizzleImpFactoryBlock factoryBlock = ^id (RSSWizzleImpProvider original, Class hookedClass, SEL selector) {
        return ^(__unsafe_unretained id self){
            RSOriginal(original)(self, selector);
        };
    };
    STAssertThrows([[RSSwizzleTestClass_A class] swizzleInstanceMethod:selector usingFactory:factoryBlock], nil);
}

-(void)testThrowsOnSwizzlingWithIncorrectImpType{
    // Different return types
    RSSwizzleImpFactoryBlock voidNoArgFactory = ^id (RSSWizzleImpProvider original, Class hookedClass, SEL selector) {
        return ^(__unsafe_unretained id self){};
    };
    STAssertThrows([[RSSwizzleTestClass_A class] swizzleInstanceMethod:@selector(methodReturningBOOL) usingFactory:voidNoArgFactory], nil);
    // Different arguments count
    STAssertThrows([[RSSwizzleTestClass_A class] swizzleInstanceMethod:@selector(methodWithArgument:) usingFactory:voidNoArgFactory], nil);
    // Different arguments type
    RSSwizzleImpFactoryBlock voidIntArgFactory = ^id (RSSWizzleImpProvider original, Class hookedClass, SEL selector) {
        return ^int(__unsafe_unretained id self){ return 0; };
    };
    STAssertThrows([[RSSwizzleTestClass_A class] swizzleInstanceMethod:@selector(methodWithArgument:) usingFactory:voidIntArgFactory], nil);
}

-(void)testThrowsOnPassingIncorrectImpFactory{
    STAssertThrows([[RSSwizzleTestClass_A class] swizzleInstanceMethod:@selector(methodWithArgument:) usingFactory:^id (RSSWizzleImpProvider original, Class hookedClass, SEL selector) {return nil;}], nil);
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
