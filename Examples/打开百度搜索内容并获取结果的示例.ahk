; ----------------------------------------------------------------------------------------
; 第1个参数是用户配置文件目录，也就是 User_Data 目录，或 "First Run" 文件所在位置。
  ; 当然，也可以像本例中一样，随便设置一个位置，这样就会用新的临时身份来打开 Chrome 。
; 第2个参数是初始打开的网址们，不填打开空白页。
; 第3个参数是自定义命令行参数，多个参数之间加空格。
  ; 无头模式:        "--headless"
  ; 浏览器标识:      "--user-agent=""标识内容"""
  ; 又无头又改标识:  "--headless --user-agent=""标识内容"""
  ; 更多其它设置，自己去搜 Chrome 命令行参数。
; 第4个参数是 Chrome.exe 位置，不填会尝试在开始菜单和注册表里找。
ChromeInst := new Chrome("User_Data")

; 原版在 new Chrome 之后不 Sleep 的话，很容易报错。
; 原因是 Chrome 还没启动好，这时 GetPageList() 将失败。
; 好消息是，这个问题已经被我修复了，所以此时的 Sleep 一般用不着了。

标签 := ChromeInst.GetPage()                                             ; 连接标签
标签.Call("Page.navigate", {"url": "https://www.baidu.com/"})            ; 打开百度
标签.WaitForLoad()                                                       ; 等待网页加载完成

js=$x("//*[contains(text(), '换一换')]")[0].click()                      ; 使用 xpath 点击换一换
标签.Evaluate(js)

; 浏览器 -> 审查元素（开发者工具） -> Elements -> Copy -> Copy JS path
; 可以快速得到后面 .Evaluate() 中需要填的内容。
; 更多复杂的操控网页需要的知识是 JS ，慢慢学习吧。
搜索内容:="我爱ahk 我爱KMCounter"
标签.Evaluate("document.getElementById('kw').value='" 搜索内容 "';")     ; 搜索框中输入文字
标签.Evaluate("document.getElementById('su').click();")                  ; 点击搜索按钮
标签.WaitForLoad()                                                       ; 等待网页加载完成

第二条搜索结果:="document.getElementById('2').innerText;"
; 对不存在的元素进行操作会报错，因此可以用 try 包裹住避免报错。
; 报错会导致跳出 try 段，因此要等待某元素直至出现，需用 loop 再包裹 try 。
loop
  try if (标签.Evaluate(第二条搜索结果).value)
  {
    MsgBox, % 标签.Evaluate(第二条搜索结果).value                        ; 打印第二条搜索结果
    break                                                                ; 元素出现了则跳出 loop
  }

弹窗内容:="Hello World!\n\n看到了吧 ahk 操控 Chrome 也是非常简单的"
标签.Evaluate("alert('" 弹窗内容 "');")                                  ; 让 Chrome 弹一个提示框出来

; 这里用到的不是 JS ，而是 Chrome API 。
; https://chromedevtools.github.io/devtools-protocol/tot/Browser/
标签.Call("Browser.close")                                               ; 关闭浏览器(所有页面和标签)
标签.Disconnect()                                                        ; 断开连接
ExitApp
return

#Include ../Chrome.ahk