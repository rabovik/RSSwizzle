//
//  RSSwizzle.h
//  RSSwizzleTests
//
//  Created by Yan Rabovik on 05.09.13.
//
//

#import <Foundation/Foundation.h>

typedef IMP (^RSSWizzleImpProvider)(void);
typedef id (^RSSwizzleImpFactoryBlock)(RSSWizzleImpProvider originalIMPProvider);

@interface RSSwizzle : NSObject

+(void)swizzleInstanceMethod:(SEL)selector
                     inClass:(Class)classToSwizzle
               newImpFactory:(RSSwizzleImpFactoryBlock)factoryBlock;

@end
