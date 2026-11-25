# Windows 11 笔记本亮度调不了？按这个顺序自查

> 症状：亮度滑块能拖动，屏幕亮度完全不变，Fn 快捷键也失效，但设备管理器里一切正常。

这份指南不绑定具体机型。每一步都会告诉你：**这条命令做什么、执行后会发生什么、看到什么结果该往哪走**。你可以只跑前两步就判断出问题在哪一层。

---

## 先确认你属于这种情况

下面三条都符合，再继续往下看：

- 设置 → 系统 → 显示 里的亮度滑块**能拖动**
- 拖动时屏幕亮度**没有任何变化**
- 设备管理器里显卡显示「工作正常」，没有黄色感叹号

不符合的话，直接看文末的[还是不行？](#还是不行)一节，那里列了其他常见原因。

## 本文的命令标记

每条命令前都有一个标记，说明它会不会改动你的系统：

| 标记 | 含义 | 能否撤销 |
|---|---|---|
| **只读** | 只查询信息，不改任何设置 | 不需要撤销 |
| **会改亮度** | 会立刻改变当前屏幕亮度 | 用同样的命令设回原值即可 |
| **会装驱动** | 会安装一个驱动包，需要管理员权限 | 可以用 `pnputil` 卸载 |

跑「会改亮度」的命令前，先记住当前亮度值，后面方便设回去。

---

## 第 1 步：亮度接口存不存在

**只读**

```powershell
Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightness
```

**执行后会发生什么**：只读取信息，不会改变任何东西。

**预期输出**：类似下面这样

```
Active            : True
CurrentBrightness : 60
InstanceName      : DISPLAY\XXX0000\...
Levels            : 101
```

**怎么判断**

| 你看到的 | 说明 | 下一步 |
|---|---|---|
| 有输出，`Levels` 是 101 左右 | 亮度接口正常 | 第 2 步 |
| 报错、或完全没有输出 | 显卡驱动没暴露亮度接口 | 见文末「接口都不存在」 |

`CurrentBrightness` 就是当前亮度百分比，先记下来。

---

## 第 2 步：写一次，看值有没有到驱动

**会改亮度**

```powershell
$m = Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightnessMethods
Invoke-CimMethod -InputObject $m -MethodName WmiSetBrightness -Arguments @{Timeout=1; Brightness=20}
```

**执行后会发生什么**：屏幕亮度立刻变成 20%（如果一切正常）。不重启，不改注册表，不改电源方案。

**预期输出**：返回一个对象，包含 `ReturnValue` 字段。`0` 表示调用成功。

然后读回来验证：

```powershell
(Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightness).CurrentBrightness
```

**只读**（这条不改变任何东西）

**怎么判断**

| 读回的值 | 屏幕 | 结论 | 下一步 |
|---|---|---|---|
| 变成 20 | 跟着变暗了 | 亮度控制是好的 | 你的问题在别处，看文末 |
| 变成 20 | **完全没变** | 值到了驱动，没到面板 | **就是本文的情况**，第 3 步 |
| 还是原来的值 | 没变 | 值没写进去 | 查权限、驱动状态 |

这一步是整个排查的分水岭。同样是「屏幕没反应」，值写没写进去，后面的方向完全相反。

---

## 第 3 步：确认控制的是不是内置屏

**只读**

```powershell
(Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightness).InstanceName
Get-PnpDevice -Class Monitor | Select-Object Status, FriendlyName
```

**执行后会发生什么**：只列出信息。

**怎么判断**

- `InstanceName` 指向的是笔记本内置屏（一般是 `DISPLAY\` 加面板厂商代码）
- 如果系统里同时挂着外接显示器，先拔掉外接屏，再回到第 2 步重试

Windows 的亮度滑块绑定在显示路径上。多屏环境下，如果它控制的是不支持 DDC/CI 的外接屏，表现和本文一模一样：拖了没反应。所以这一步必须先排除。

---

## 第 4 步：OEM 扩展驱动还在不在

**只读**

```powershell
pnputil /enum-drivers
```

**执行后会发生什么**：列出系统里所有已安装的驱动包，不修改任何东西。

输出很长，重点看 **Class Name 是 `Extension`**、并且 Provider 是显卡厂商（Intel / AMD / NVIDIA）的那几条。Intel 的扩展包名字通常叫 `iigd_ext.inf`，发布名是 `oemNN.inf`。

**怎么判断**

| 你看到的 | 说明 | 下一步 |
|---|---|---|
| 找不到 Intel 的 Extension 包 | 扩展驱动缺失，很可能就是它 | 第 5 步 |
| 有 Extension 包 | 可能不是这个原因 | 文末「其他可能」 |
| 不确定 | 用第 5 步反查更准 | 第 5 步 |

---

## 第 5 步：Windows Update 里有没有可装的扩展

**只读**

```powershell
$session  = New-Object -ComObject Microsoft.Update.Session
$searcher = $session.CreateUpdateSearcher()
$result   = $searcher.Search("IsInstalled=0 and Type='Driver'")
foreach ($u in $result.Updates) {
    "[{0}] {1}" -f $u.DriverClass, $u.Title
    "    HWID: {0}" -f $u.DriverHardwareID
}
```

**执行后会发生什么**：只查询可用的驱动更新，不会下载，也不会安装。

**预期输出**：零到若干条驱动更新，每条带 `DriverClass` 和硬件 ID。

**怎么判断**

先拿到你这台机器显卡的硬件 ID：

```powershell
Get-CimInstance Win32_VideoController | Select-Object Name, PNPDeviceID
```

然后在第 5 步的结果里找 `[Extension]` 开头、并且 `HWID` 是显卡 `PNPDeviceID` 前缀的那一条（忽略大小写）。

找到了就说明扩展可以装回来，进第 6 步。

---

## 第 6 步：装回来

**会装驱动**

图形界面：

设置 → Windows 更新 → 高级选项 → 可选更新 → 驱动程序更新 → 勾选那条 Extension → 安装。

命令行（管理员 PowerShell）：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\fix-install-extension.ps1
```

**执行后会发生什么**：从 Windows Update 下载那个驱动包并安装。可能会提示重启，不会动你的个人文件。

**装完怎么验证**：回到第 2 步，再跑一次亮度写入。

**如果装完出了问题，怎么撤销**：

```powershell
pnputil /enum-drivers | Select-String -Pattern 'iigd_ext' -Context 0,6
pnputil /delete-driver oemNN.inf /uninstall
```

把 `oemNN.inf` 换成上一条命令里查到的发布名。

---

## 原理

Intel 的显卡驱动安装包在升级主驱动时，会清理同一设备上的旧驱动包。OEM 提供的 Extension 扩展驱动和主驱动类 GUID 不同，但共用同一个 `oemNN.inf` 槽位。主驱动占了槽位，扩展就被一起删掉，而新驱动不会主动把它装回来。

主驱动是通用版本：能识别面板，能接受亮度数值，但不包含 OEM 针对具体面板写的背光适配参数。所以出现这种状态：

```
拖动滑块 → Windows 写入亮度值 → 显卡驱动接受并记录 → 值停在这里，没送到面板
```

Fn 快捷键走同一条底层路径，所以一起失效。设备管理器看不出问题，因为驱动本身没坏，缺的是一块配套的拼图。

其他品牌同理。这类「主驱动 + 扩展驱动」的组合在笔记本上很常见，扩展包里通常放着厂商为自家屏幕写的参数。

---

## 还是不行？

### 接口都不存在

第 1 步就没有输出，说明显卡驱动没有暴露亮度接口。按这个顺序查：

1. 设备管理器 → 显示适配器，看是不是「Microsoft 基本显示适配器」。是的话显卡驱动根本没装上。
2. 重装厂商官网的显卡驱动，不要用驱动精灵之类的第三方工具。
3. 装完重启，再跑第 1 步。

### 值写不进去

第 2 步读回的值没变。可能的原因：

- PowerShell 没有以当前用户正常运行
- 组策略或管理软件限制了显示设置
- 驱动处于异常状态，重启后重试

### 值写进去了，屏幕也不动，但不是这个原因

- **自适应亮度开着**：设置 → 系统 → 显示 → 亮度，关掉「当光线变化时自动更改亮度」。也可以在电源选项里关。
- **内容自适应亮度（CABC）**：部分 Intel 机器在电池模式下会根据画面内容调整亮度，让手动调节看起来没效果。注册表 `HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers` 下的 `CABCOption` 改成 `0` 可以关闭。
- **厂商电源管理软件**：某些品牌的管家类软件会接管亮度，试着退出它再调。
- **驱动版本本身有问题**：退回上一版驱动，或者装厂商官网的 OEM 版本。
- **屏幕硬件问题**：如果外接显示器正常、内置屏在任何系统下都不能调，考虑排线或背光故障。

### 外接显示器不能调

这是正常的。Windows 只能通过 DDC/CI 控制支持该协议的外接屏，很多显示器不支持，或者需要在显示器菜单里手动开启 DDC/CI。

---

## 仓库里的脚本

| 脚本 | 作用 | 是否改动系统 |
|---|---|---|
| `scripts/diagnose-brightness.ps1` | 一次性打印 7 项检查结果 | 只读 |
| `scripts/verify-brightness.ps1` | 亮度 90→10→60 扫描，肉眼验证 | 会改亮度（临时） |
| `scripts/fix-install-extension.ps1` | 按硬件 ID 匹配并安装扩展驱动 | 会装驱动 |

运行方式：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\diagnose-brightness.ps1
```

`fix-install-extension.ps1` 需要管理员权限，脚本启动时会自己检查。

---

## 适用范围

- 在 Windows 11 + Intel 核显的笔记本上验证过
- 其他平台（AMD、NVIDIA）的原理类似，但命令和注册表位置不同，不要直接套用
- 安装扩展驱动属于系统级改动，建议先创建还原点

## English Summary

**Symptom.** The Windows 11 brightness slider moves but the screen never changes; Fn brightness keys fail too.

**Root cause.** A graphics driver update can uninstall the OEM-provided Extension driver that shares the same `oemNN.inf` slot as the main display driver. The generic driver accepts brightness values but lacks the OEM panel adaptation needed to drive the backlight.

**How to locate it.** Write a brightness value through `WmiSetBrightness`, read it back, and compare with what the screen does. If the value changes but the panel does not, the fault sits between the driver and the panel. Check whether an OEM Extension driver is installed, then look for a matching optional driver update in Windows Update.

**Fix.** Reinstall the Extension driver from Windows Update → Advanced options → Optional updates → Driver updates, or run `scripts/fix-install-extension.ps1` from an elevated PowerShell.

## License

MIT
