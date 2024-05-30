; ----------------------------------------------------------------------------------------
; 第1个参数是用户配置文件目录，也就是 User_Data 目录，或 "First Run" 文件所在位置。
  ; 当然，也可以像本例中一样，随便设置一个位置，这样就会用新的临时身份来打开 Chrome 。
; 第2个参数是初始打开的网址们，不填打开空白页。
; 第3个参数是自定义命令行参数，多个参数之间加空格。
  ; 无头模式:               "--headless"
  ; 浏览器标识:             "--user-agent=""标识内容"""
  ; 既设置无头模式又改标识: "--headless --user-agent=""标识内容"""
  ; 更多其它设置，自己去搜 Chrome 命令行参数。
; 第4个参数是 Chrome.exe 位置，不填会尝试在开始菜单和注册表里找。
ChromeInst := new Chrome("User_Data")

标签 := ChromeInst.GetPage()                                                     ; 连接当前标签
标签.Url := "https://www.baidu.com/"                                             ; 打开百度
标签.WaitForLoad()                                                               ; 等待网页加载完成

; 对于使用 querySelector 或 querySelectorAll 等方法获取的元素
; 支持元素在 JS 中的全部属性与方法（注意：大小写必须与 JS 中的保持一致）
; 选择元素虽然支持 .getElementById() 等方法，但建议只用 .querySelector()
; 因为通过浏览器 -> 审查元素（开发者工具） -> Elements -> Copy -> Copy JS path
; 可以快速得到 .querySelector() 中需要填的内容
标签.querySelector("#hotsearch-refresh-btn").click()                             ; 调用元素的 js 方法，点击换一换按钮

元素集 := 标签.querySelectorAll("li.hotsearch-item")                             ; 获取元素集
MsgBox % 元素集[1].textContent                                                   ; 读属性
MsgBox % 元素集[2].InnerHTML                                                     ; 读属性但失败，因为大小写错误
元素集[3].innerHTML := "写属性就是这么简单"                                      ; 写属性
MsgBox 注意看，第3条热搜被改了

标签.getElementById("kw").value := "我爱ahk 我爱KMCounter"                       ; 在搜索框中输入文字
标签.getElementById("su").click()                                                ; 点击搜索按钮
标签.WaitForLoad()                                                               ; 等待网页加载完成

while (!标签.getElementById("2"))                                                ; 等待元素出现
  Sleep 1000
MsgBox % 标签.getElementById("2").innerText                                      ; 打印第二条搜索结果

标签.Evaluate("alert('看到了吧！\nahk 操控 Chrome 也是非常简单的！')")           ; 执行 JS 代码让 Chrome 弹一个提示框

; 这里用到的不是 JS ，而是 Chrome API 。
; https://chromedevtools.github.io/devtools-protocol/tot/Browser/
MsgBox % 标签.Call("Browser.getVersion").userAgent                               ; 获取浏览器 userAgent

标签.Close()                                                                     ; 关闭标签

ExitApp

#Include ../Chrome.ahk