# libmpv-bundles

libmpv (dynamic libraries) bundles under the LGPL:

| Asset | Source |
| --- | --- |
| `libmpv-win-x64.zip` | from official mpv LGPL Windows build |
| `libmpv-win-arm64.zip` | from official mpv LGPL Windows build |
| `libmpv-linux-x64.tar.gz` | built from source on Ubuntu 24.04 |
| `libmpv-linux-arm64.tar.gz` | built from source on Ubuntu 24.04 arm64 |

Linux builds enable LuaJIT so standard options such as `osc` are available.
They also enable VAAPI, EGL, Wayland and X11 so libmpv's render API can use
zero-copy VAAPI hardware decoding with an application-provided GL context.
