
# RSSwizzle
Safe method swizzling done right.

_Detailed description not ready yet._

## Example
Dealloc swizzling:

```objective-c
Class classToSwizzle = [MyClass class];
SEL selector = NSSelectorFromString(@"dealloc");
[RSSwizzle
 swizzleInstanceMethod:selector
 inClass:classToSwizzle
 newImpFactory:^id(RSSWizzleImpProvider originalIMPProvider) {
     return ^void(__unsafe_unretained id self){
         
	 NSLog(@"Code before dealloc");
         
         void (*originalIMP)(__unsafe_unretained id, SEL);
         originalIMP = (__typeof(originalIMP))originalIMPProvider();
         originalIMP(self,selector);
     };
 }];
```


## Requirements
* iOS 5.0+
* Mac OS X 10.7+
* ARC

## Author
Yan Rabovik ([@rabovik][twitter] on twitter)

## License
MIT License.

[twitter]: https://twitter.com/rabovik
