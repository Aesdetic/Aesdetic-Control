#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The "aesdetic_logo" asset catalog image resource.
static NSString * const ACImageNameAesdeticLogo AC_SWIFT_PRIVATE = @"aesdetic_logo";

/// The "product_image" asset catalog image resource.
static NSString * const ACImageNameProductImage AC_SWIFT_PRIVATE = @"product_image";

#undef AC_SWIFT_PRIVATE
