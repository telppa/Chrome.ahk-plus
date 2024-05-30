ChromeInst := new Chrome("User_Data")

标签 := ChromeInst.GetPage( , , "Callback")                   ; 连接当前标签并为标签发生的事件设置回调函数

标签.Call("Network.enable")                                   ; 开启 Network 事件监听
标签.Url := "https://www.baidu.com/"                          ; 打开百度
标签.WaitForLoad()                                            ; 等待网页加载完成
标签.Call("Network.disable")                                  ; 获取到目标内容后，及时关闭 Network 事件监听

Sleep 10000

标签.Call("Browser.close")                                    ; 关闭浏览器(所有页面和标签)
ExitApp

Callback(Event)
{
	if (Event.Method == "Network.requestWillBeSent")
	{
		; 这里会得到很多 requestId ，这是因为除网页本身还有各种资源（如图片）请求加载
		ToolTip % Event.params.requestId
	}
}

#Include ../Chrome.ahk