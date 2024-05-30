# Chrome.ahk-plus

Automate Google Chrome and MS Edge using native AutoHotkey.  
使用纯 AutoHotkey 操控 Chrome 和 Edge 。


## What has been enhanced compared to Chrome.ahk

* Significantly simplifies the manipulation of elements and frames.
* `Google Chrome` and `Microsoft Edge` are supported.
* Error reports directed to user code instead of library code.
* Added 30-seconds timeout for all funtions that could cause a dead loop.
* Simplified creation of ProfilePath.
* Fixed an issue that Chrome to report error due to slow opening.
* Fixed an issue that Chrome to report error due to shortcuts were not found.
* 基于 GeekDude 2023.03.21 Release 版修改，与 GeekDude 版相比有以下增强。
* 大幅简化元素及框架的操作。
* 支持`谷歌 Chrome`、`微软 Edge`、`百分浏览器`。
* 报错可直接定位到用户代码，而不是库代码。
* 为所有可能造成死循环的地方添加了默认30秒的超时参数。
* 简化了 Chrome 用户配置目录的创建。
* 修复了 Chrome 打开缓慢而报错的问题。
* 修复了找不到开始菜单中的 Chrome 快捷方式而报错的问题。


## How to use

**You can find more sample code showing how to use this library in the Examples folder.**  
**Examples 目录下有更多示例。**


## Basic Demo

```AutoHotkey
#Include Chrome.ahk

; Create an instance of the Chrome class using
; the folder ChromeProfile to store the user profile
ChromeInst := new Chrome("ChromeProfile")

; Connect to the newly opened tab and navigate to another website
PageInst := ChromeInst.GetPage()
PageInst.Url := "https://autohotkey.com/"
PageInst.WaitForLoad()

; Print the element's outerHTML value
MsgBox % PageInst.querySelector("#MainTitle").outerHTML

; Return a screenshot of the element (base64 encoded),
base64 := PageInst.querySelector("#MainTitle").Screenshot()

; You can show or save it as an image file by using the ImagePut library.
; https://github.com/iseahound/ImagePut
; ImageShow(base64)

; Execute some JavaScript
PageInst.Evaluate("alert('Hello World!');")

; Close the page
PageInst.Close()

ExitApp
return
```


## Switching Between Frame

![alt text](https://i.ibb.co/PW2P9ZG/Rufaydium-Frames-Example.png)

Example for TAB/Page 1

```AutoHotkey
PageInst.SwitchToFrame(1)       ; switching to frame A
PageInst.GetElementById(someid) ; this will get element from frame A
PageInst.SwitchToFrame(2)       ; switching to frame B
PageInst.GetElementById(someid) ; this will get element from frame B
PageInst.SwitchToFrame(2, 1)    ; switching to frame BA
PageInst.GetElementById(someid) ; this will get element from frame BA
PageInst.SwitchToFrame(2)       ; switch back to Frame B
PageInst.SwitchToMainPage()     ; switch back to Main Page / Main frame
```

Example for TAB/Page 1

```AutoHotkey
PageInst.SwitchToFrame(1)            ; switching to frame A
PageInst.GetElementById(someid)      ; this will get element from frame A
PageInst.SwitchToFrameByName("B")    ; switching to frame B by name
PageInst.GetElementById(someid)      ; this will get element from frame B
PageInst.SwitchToFrameByURL(urlOfBA) ; switching to frame BA by url
PageInst.GetElementById(someid)      ; this will get element from frame BA
PageInst.SwitchToFrame(2)            ; switch back to Frame B
PageInst.SwitchToMainPage()          ; switch back to Main Page / Main frame
```

Example for TAB/Page 2

```AutoHotkey
PageInst.SwitchToFrame(1)   ; switching to frame X
PageInst.SwitchToFrame(2)   ; switching to frame Y
PageInst.SwitchToFrame(3)   ; switching to frame Z
PageInst.SwitchToMainPage() ; switch back to Main Page / Main frame
```
