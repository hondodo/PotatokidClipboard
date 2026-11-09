/// 非 io 平台（web 等）：无法获取 ABI，返回空串（check 不带 abi，
/// 服务端回落通用包）。
String currentAbi() => '';
