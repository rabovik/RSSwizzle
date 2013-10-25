
# RSSwizzle
Safe method swizzling done right.

## Motivation

Classical method swizzling with `method_exchangeImplementations` is quite simple, but it has a lot of limitations:

* It is safe only if swizzling is done in the `+load` method. If you need to swizzle methods during application's lifetime you should take into account that third-party code may do swizzling of the same method in another thread at the same time.
* The swizzled method must be implemented by the class itself and not by superclasses. Workarounds by copying implementation from the superclass do not really work. Original implementation in the superclass must be fetched at the time of calling, not at the time of swizzling <sup>([1][774],[2][775])</sup>.
* The swizzled method implementation must not rely on the `_cmd` argument. _(And generally you can not be sure in it <sup>([5][cmd])</sup>.)_
* Naming conflicts are possible <sup>([3][SO])</sup>.

For more details see discussions in: [1][774], [2][775], [3][SO], [4][TH], [5][cmd].

**RSSwizzle** avoids all these known pitfalls.

## Usage

Original implementation must always be called from the new implementation. And because of the the fact that for safe and robust swizzling original implementation must be dynamically fetched at the time of calling and not at the time of swizzling <sup>([1][774],[2][775])</sup>, swizzling API is a little bit complicated.

You should pass a factory block that returns the block for the new implementation of the swizzled method. And use `swizzleInfo` argument to retrieve and call original implementation.

Example for swizzling `-(int)calculate:(int)number;` method in class `TestClass`:


```objective-c
[TestClass swizzleInstanceMethod:@selector(calculate:) usingFactory:^id (RSSWizzleIMPProvider original, __unsafe_unretained Class swizzledClass, SEL selector) {
   //The following block will be used as the new implementation.
   return ^int (__unsafe_unretained TestClass *self, int number) {
       //You MUST always cast implementation to the correct function pointer.
       int orig = ((__typeof(int (*)(__unsafe_unretained id, SEL, ...)))original())(self, selector, number);

       //Returning modified return value.
       return orig+1;
   };
}];
```

To simplify that, RSSwizzle offers some very useful macros to help clean up your code:

```objective-c
[TestClass swizzleInstanceMethod:@selector(calculate:) usingFactory:^ RSSwizzleFactory {
   //The following block will be used as the new implementation.
   return ^ RSSwizzleReplacement(int, TestClass *, int number) {
       //You MUST always cast implementation to the correct function pointer.
       int orig = RSOriginalCast(int, original)(self, selector, number);

       //Returning modified return value.
       return orig+1;
   };
}];
```

#### Modes

Most of the time swizzling goes along with checking whether this particular class (or one of its superclasses) has been already swizzled. Here the `mode` and `key` parameters can help.
Possible mode values:

* `RSSwizzleModeAlways` **RSSwizzle** always does swizzling regardless of the given `key`.
* `RSSwizzleModeOncePerClass` **RSSwizzle** does not do swizzling if the same class has been swizzled earlier with the same `key`.
* `RSSwizzleModeOncePerClassAndSuperclasses` **RSSwizzle** does not do swizzling if the same class or one of its superclasses have been swizzled earlier with the same `key`.

Here is an example of swizzling `-(void)dealloc;` only in case when neither class and no one of its superclasses has been already swizzled with the given `key`:

```objective-c
static const void *key = &key;
[TestClass swizzleInstanceMethod:@selector(calculate:) usingFactory:^ RSSwizzleFactory {
   return ^ RSSwizzleReplacement(int, TestClass *) {
       NSLog(@"Deallocating %@.",self);
       RSOriginalVoid(original)(self, selector);
   };
} mode:RSSwizzleModeOncePerClassAndSuperclasses key:key];
```

> **Note:** `RSSwizzleModeOncePerClassAndSuperclasses ` mode does not guarantees that your implementation will be called only once per method call. If the order of swizzling is: first inherited class, second superclass; then both swizzlings will be done and the new implementation will be called twice.

#### Thread safety

**RSSwizzle** is fully thread safe. You do not need any additional synchronization.

## CocoaPods
Add `RSSwizzle` to your _Podfile_.

## Requirements
* iOS 5.0+
* Mac OS X 10.7+
* ARC

## Author
Yan Rabovik ([@rabovik][twitter] on twitter)

## License
MIT License.

[twitter]: https://twitter.com/rabovik
[cmd]: http://www.mikeash.com/pyblog/friday-qa-2010-01-29-method-replacement-for-fun-and-profit.html#comment-e2c2af6395d9e8fca559895bbd434ee8
[SO]: http://stackoverflow.com/a/8636521/441735
[774]: https://github.com/ReactiveCocoa/ReactiveCocoa/pull/774
[775]: https://github.com/ReactiveCocoa/ReactiveCocoa/pull/775
[TH]: https://github.com/th-in-gs/THObserversAndBinders/commit/cabe12dece2faabf5e58759363ac603be963c889#L1R231