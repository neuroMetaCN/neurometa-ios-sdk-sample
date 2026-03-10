# NeuroMeta iOS SDK Binary Package (Vendored)

该目录是 `NeuroMetaSDK` 的二进制分发副本，供 `neurometa-ios-demo` 直接引用。

## 说明

- 本目录用于对外发布 Demo，避免暴露 SDK 源码。
- 产物由内部 `neurometa-ios-sdk` 仓库生成后拷贝到此目录。
- 当前产物使用 `-allow-internal-distribution` 打包，建议构建与接入使用同主版本 Xcode。

## 当前内容

- `NeuroMetaSDK.xcframework`
- `NeuroMetaSDK.xcframework.zip`
- `checksum.txt`
- `Package.swift` (`binaryTarget` 配置)

## 更新方式

1. 在内部 SDK 仓库执行 `./scripts/build_binary_package.sh`
2. 用新产物覆盖本目录内容
