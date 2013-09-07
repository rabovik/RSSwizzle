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

@interface RSSwizzleTestClass_A : NSObject @end
@implementation RSSwizzleTestClass_A
-(int)calc:(int)num{ return num; }
-(BOOL)methodReturningBOOL{ return YES; };
-(void)methodWithArgument:(id)arg{};
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


static void swizzleDealloc(Class classToSwizzle, dispatch_block_t blockBefore){
    SEL selector = NSSelectorFromString(@"dealloc");
    [RSSwizzle
     swizzleInstanceMethod:selector
     inClass:classToSwizzle
     newImpFactory:^id(RSSWizzleImpProvider originalIMPProvider) {
         return ^void(__unsafe_unretained id self){
             blockBefore();
             
             void (*originalIMP)(__unsafe_unretained id, SEL);
             originalIMP = (__typeof(originalIMP))originalIMPProvider();
             originalIMP(self,selector);
         };
     }];
}

static void swizzleNumber(Class classToSwizzle, int(^transformationBlock)(int)){
    SEL selector = NSSelectorFromString(@"calc:");
    [RSSwizzle
     swizzleInstanceMethod:selector
     inClass:classToSwizzle
     newImpFactory:^id(RSSWizzleImpProvider originalIMPProvider) {
         return ^int(__unsafe_unretained id self, int num){
             int (*originalIMP)(__unsafe_unretained id, SEL, int);
             originalIMP = (__typeof(originalIMP))originalIMPProvider();
             int res = originalIMP(self,selector,num);
             
             return transformationBlock(res);
         };
     }];
}

@interface RSSwizzleTests : SenTestCase @end

@implementation RSSwizzleTests

+(void)setUp{
    [self swizzleDeallocs];
    [self swizzleCalc];
}

-(void)setUp{
    [super setUp];
    CLEAR_LOG();
}

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

#if !defined(NS_BLOCK_ASSERTIONS)
-(void)testThrowsOnSwizzlingNonexistentMethod{
    SEL selector = NSSelectorFromString(@"nonexistent");
    RSSwizzleImpFactoryBlock factoryBlock = ^id(RSSWizzleImpProvider originalIMPProvider){
        return ^(__unsafe_unretained id self){
            void (*originalIMP)(__unsafe_unretained id, SEL);
            originalIMP = (__typeof(originalIMP))originalIMPProvider();
            originalIMP(self,selector);
        };
    };
    STAssertThrows([RSSwizzle
                    swizzleInstanceMethod:selector
                    inClass:[RSSwizzleTestClass_A class]
                    newImpFactory:factoryBlock], nil);
}

-(void)testThrowsOnSwizzlingWithIncorrectImpType{
    // Different return types
    RSSwizzleImpFactoryBlock voidNoArgFactory =
        ^id(RSSWizzleImpProvider originalIMPProvider)
    {
        return ^(__unsafe_unretained id self){};
    };
    STAssertThrows([RSSwizzle
                    swizzleInstanceMethod:@selector(methodReturningBOOL)
                    inClass:[RSSwizzleTestClass_A class]
                    newImpFactory:voidNoArgFactory], nil);
    // Different arguments count
    STAssertThrows([RSSwizzle
                    swizzleInstanceMethod:@selector(methodWithArgument:)
                    inClass:[RSSwizzleTestClass_A class]
                    newImpFactory:voidNoArgFactory], nil);
    // Different arguments type
    RSSwizzleImpFactoryBlock voidIntArgFactory =
    ^id(RSSWizzleImpProvider originalIMPProvider)
    {
        return ^int(__unsafe_unretained id self){ return 0; };
    };
    STAssertThrows([RSSwizzle
                    swizzleInstanceMethod:@selector(methodWithArgument:)
                    inClass:[RSSwizzleTestClass_A class]
                    newImpFactory:voidIntArgFactory], nil);
}

-(void)testThrowsOnPassingIncorrectImpFactory{
    STAssertThrows([RSSwizzle
                    swizzleInstanceMethod:@selector(methodWithArgument:)
                    inClass:[RSSwizzleTestClass_A class]
                    newImpFactory:^id(id x){ return nil; }], nil);
}
#endif

@end
