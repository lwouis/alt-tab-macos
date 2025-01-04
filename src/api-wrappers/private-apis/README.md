Private APIs are APIs that we can build the app against, but they are not supported or documented by Apple
We can see their names as symbols in the SDK (see https://github.com/lwouis/MacOSX-SDKs)
However their full signature is a best-effort of retro-engineering
Very little information is available about private APIs. I tried to document them as much as possible here

Some links:

* Webkit repo: https://github.com/WebKit/webkit/blob/master/Source/WebCore/PAL/pal/spi/cg/CoreGraphicsSPI.h
* Alt-tab-macos issue: https://github.com/lwouis/alt-tab-macos/pull/87#issuecomment-558624755
* Github repo with retro-engineered internals: https://github.com/NUIKit/CGSInternal
