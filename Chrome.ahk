; Chrome.ahk-plus v1.4.0
; https://github.com/telppa/Chrome.ahk-plus

; 基于 GeekDude 2023.03.21 Release 版修改，与 GeekDude 版相比有以下增强。
; 大幅简化元素及框架的操作。
; 支持谷歌 Chrome 与微软 Edge 。
; 报错可直接定位到用户代码，而不是库代码。
; 为所有可能造成死循环的地方添加了默认30秒的超时参数。
; 简化了 Chrome 用户配置目录的创建。
; 修复了 Chrome 打开缓慢而报错的问题。
; 修复了找不到开始菜单中的 Chrome 快捷方式而报错的问题。

; page.Call() 支持的参数与命令行支持的参数
; https://chromedevtools.github.io/devtools-protocol/tot/Browser/
; https://peter.sh/experiments/chromium-command-line-switches/

; 注意事项：
; 相同的 ProfilePath ，无法指定不同的 DebugPort ，会被 Chrome 自动修改为相同的 DebugPort 。
; 不要在 page.Evaluate() 前加 Critical ，这会导致 Evaluate() 返回不了值，而你很难发现它出错了。
; 为了与 GeekDude 版保持兼容性，本增强版从 1.3.5 开始调换了所有 Timeout 参数的位置，故可能与本增强版的旧版不兼容。

; 以后的人要想同步更新这个库，强烈建议使用 BCompare 之类的比较程序，比较着 GeekDude Release 版本进行更新。
; 不要尝试用未 Release 版本（即代码中有 “#Include JSON.ahk” “#Include WebSocket.ahk” 字样）进行更新。
; 因为这样会有太多坑，你要么搞不定，要么会浪费很多无谓的时间！！！！！！

class Chrome
{
	static Version := "1.4.0"
	
	static DebugPort := 9222
	
	/*
		Escape a string in a manner suitable for command line parameters
	*/
	CliEscape(Param)
	{
		return """" RegExReplace(Param, "(\\*)""", "$1$1\""") """"
	}
	
	/*
		Finds instances of chrome in debug mode and the ports they're running
		on. If no instances are found, returns a false value. If one or more
		instances are found, returns an associative array where the keys are
		the ports, and the values are the full command line texts used to start
		the processes.
		
		One example of how this may be used would be to open chrome on a
		different port if an instance of chrome is already open on the port
		you wanted to used.
		
		```
		; If the wanted port is taken, use the largest taken port plus one
		DebugPort := 9222
		if (Chromes := Chrome.FindInstances()).HasKey(DebugPort)
			DebugPort := Chromes.MaxIndex() + 1
		ChromeInst := new Chrome(ProfilePath,,,, DebugPort)
		```
		
		Another use would be to scan for running instances and attach to one
		instead of starting a new instance.
		
		```
		if (Chromes := Chrome.FindInstances())
			ChromeInst := {"base": Chrome, "DebugPort": Chromes.MinIndex()}
		else
			ChromeInst := new Chrome(ProfilePath)
		```
	*/
	FindInstances()
	{
		static Needle := "--remote-debugging-port=(\d+)"
		
		for k, v in ["chrome.exe", "msedge.exe"]
		{
			Out := {}
			for Item in ComObjGet("winmgmts:")
				.ExecQuery("SELECT CommandLine FROM Win32_Process"
				. " WHERE Name = '" v "'")
				; https://learn.microsoft.com/zh-cn/windows/win32/cimwin32prov/win32-process
				if RegExMatch(Item.CommandLine, Needle, Match)
					Out[Match1] := Item.CommandLine
			
			if (Out.MaxIndex())
				break
		}
		return Out.MaxIndex() ? Out : False
	}
	
	/*
		ProfilePath - Path to the user profile directory to use. Will use the standard if left blank.
		URLs        - The page or array of pages for Chrome to load when it opens
		Flags       - Additional flags for chrome when launching
		ChromePath  - Path to chrome.exe, will detect from start menu when left blank
		DebugPort   - What port should Chrome's remote debugging server run on
	*/
	__New(ProfilePath:="ChromeProfile", URLs:="about:blank", Flags:="", ChromePath:="", DebugPort:="")
	{
		if (ProfilePath == "")
			throw Exception("Need a profile directory", -1)
		; Verify ProfilePath
		if (!InStr(FileExist(ProfilePath), "D"))
		{
			FileCreateDir, %ProfilePath%
			if (ErrorLevel = 1)
				throw Exception("Failed to create the profile directory", -1)
		}
		cc := DllCall("GetFullPathName", "str", ProfilePath, "uint", 0, "ptr", 0, "ptr", 0, "uint")
		VarSetCapacity(buf, cc*(A_IsUnicode?2:1))
		DllCall("GetFullPathName", "str", ProfilePath, "uint", cc, "str", buf, "ptr", 0, "uint")
		this.ProfilePath := ProfilePath := buf
		
		; Try to find chrome or msedge path
		if (ChromePath == "")
		{
			; Try to find chrome path
			if !FileExist(ChromePath)
				; By using winmgmts to get the path of a shortcut file we fix an edge case where the path is retreived incorrectly
				; if using the ahk executable with a different architecture than the OS (using 32bit AHK on a 64bit OS for example)
				try ChromePath := ComObjGet("winmgmts:").ExecQuery("Select * from Win32_ShortcutFile where Name=""" StrReplace(A_StartMenuCommon "\Programs\Google Chrome.lnk", "\", "\\") """").ItemIndex(0).Target
			
			if !FileExist(ChromePath)
				RegRead, ChromePath, HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe
			
			; Try to find msedge path
			if !FileExist(ChromePath)
				try ChromePath := ComObjGet("winmgmts:").ExecQuery("Select * from Win32_ShortcutFile where Name=""" StrReplace(A_StartMenuCommon "\Programs\Microsoft Edge.lnk", "\", "\\") """").ItemIndex(0).Target
			
			if !FileExist(ChromePath)
				RegRead ChromePath, HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe
		}
		
		; Verify ChromePath
		if !FileExist(ChromePath)
			throw Exception("Chrome and Edge could not be found", -1)
		this.ChromePath := ChromePath
		
		; Verify DebugPort
		if (DebugPort != "")
		{
			if DebugPort is not integer
				throw Exception("DebugPort must be a positive integer", -1)
			else if (DebugPort <= 0)
				throw Exception("DebugPort must be a positive integer", -1)
			this.DebugPort := DebugPort
		}
		
		; Escape the URL(s)
		URLString := ""
		for Index, URL in IsObject(URLs) ? URLs : [URLs]
			URLString .= " " this.CliEscape(URL)
		
		Run, % this.CliEscape(ChromePath)
		. " --remote-debugging-port=" this.DebugPort
		. " --remote-allow-origins=*"
		. (ProfilePath ? " --user-data-dir=" this.CliEscape(ProfilePath) : "")
		. (Flags ? " " Flags : "")
		. URLString
		,,, OutputVarPID
		this.PID := OutputVarPID
	}
	
	/*
		End Chrome by terminating the process.
	*/
	Kill()
	{
		Process, Close, % this.PID
	}
	
	/*
		Queries chrome for a list of pages that expose a debug interface.
		In addition to standard tabs, these include pages such as extension
		configuration pages.
	*/
	GetPageList(Timeout:=30)
	{
		http := ComObjCreate("WinHttp.WinHttpRequest.5.1")
		StartTime := A_TickCount
		loop
		{
			; It is easy to fail here because "new chrome()" takes a long time to execute.
			; Therefore, it will be tried again and again within 30 seconds until it succeeds or timeout.
			; 极端情况可能出现因为 page.Call("Browser.close",, false) 不等待返回值的关闭了浏览器
			; 然后又极快的使用 FindInstances() 附着在了正在关闭的 chrome 进程上导致超时
			; 实际案例就是在聚合翻译器的重启功能上
			if (A_TickCount-StartTime > Timeout*1000)
				throw Exception("Get page list timeout")
			else
				try
				{
					http.Open("GET", "http://127.0.0.1:" this.DebugPort "/json", true)
					http.Send()
					http.WaitForResponse(-1)
					if (http.Status = 200)
						break
				}
			
			Sleep 50
		}
		return this.JSON.Load(http.responseText)
	}
	
	/*
		Returns a connection to the debug interface of a page that matches the
		provided criteria. When multiple pages match the criteria, they appear
		ordered by how recently the pages were opened.
		
		Key        - The key from the page list to search for, such as "url" or "title"
		Value      - The value to search for in the provided key
		MatchMode  - What kind of search to use, such as "exact", "contains", "startswith", or "regex"
		Index      - If multiple pages match the given criteria, which one of them to return
		FnCallback - A function to be called whenever message is received from the page
		Timeout    - Maximum number of seconds to wait for the page connection
	*/
	GetPageBy(Key, Value, MatchMode:="exact", Index:=1, FnCallback:="", FnClose:="", Timeout:=30)
	{
		try
		{
			Count := 0
			for n, PageData in this.GetPageList()
			{
				if (((MatchMode = "exact" && PageData[Key] = Value) ; Case insensitive
					|| (MatchMode = "contains" && InStr(PageData[Key], Value))
					|| (MatchMode = "startswith" && InStr(PageData[Key], Value) == 1)
					|| (MatchMode = "regex" && PageData[Key] ~= Value))
					&& ++Count == Index)
					return new this.Page(PageData.webSocketDebuggerUrl, FnCallback, FnClose, Timeout)
			}
		}
		catch e
			throw Exception(e.Message, -1)
	}
	
	/*
		Shorthand for GetPageBy("url", Value, "startswith")
	*/
	GetPageByURL(Value, MatchMode:="startswith", Index:=1, FnCallback:="", FnClose:="", Timeout:=30)
	{
		try
			return this.GetPageBy("url", Value, MatchMode, Index, FnCallback, FnClose, Timeout)
		catch e
			throw Exception(e.Message, -1)
	}
	
	/*
		Shorthand for GetPageBy("title", Value, "startswith")
	*/
	GetPageByTitle(Value, MatchMode:="startswith", Index:=1, FnCallback:="", FnClose:="", Timeout:=30)
	{
		try
			return this.GetPageBy("title", Value, MatchMode, Index, FnCallback, FnClose, Timeout)
		catch e
			throw Exception(e.Message, -1)
	}
	
	/*
		Shorthand for GetPageBy("type", Type, "exact")
		
		The default type to search for is "page", which is the visible area of
		a normal Chrome tab.
	*/
	GetPage(Index:=1, Type:="page", FnCallback:="", FnClose:="", Timeout:=30)
	{
		try
			return this.GetPageBy("type", Type, "exact", Index, FnCallback, FnClose, Timeout)
		catch e
			throw Exception(e.Message, -1)
	}
	
	/*
		Connects to the debug interface of a page given its WebSocket URL.
	*/
	class Page
	{
		Connected    := False
		Id           := 0
		Responses    := []
		TargetId     := ""
		Root         := ""
		NodeId       := ""
		
		/*
			WsUrl      - The desired page's WebSocket URL
			FnCallback - A function to be called whenever message is received
			FnClose    - A function to be called whenever the page connection is lost
			Timeout    - Maximum number of seconds to wait for the page connection
		*/
		__New(WsUrl, FnCallback:="", FnClose:="", Timeout:=30)
		{
			this.FnCallback := FnCallback
			this.FnClose := FnClose
			; Here is no waiting for a response so no need to add a timeout
			; The method has a hide param in the first, so we need pass this in first
			this.BoundKeepAlive := this.Call.Bind(this, "Browser.getVersion",, False)
			
			; TODO: Throw exception on invalid objects
			if IsObject(WsUrl)
				WsUrl := WsUrl.webSocketDebuggerUrl
			
			; MUST PASS AN ADDRESS INSTEAD OF A VALUE
			; or it will create circular references like the following
			; this.ws.base.parent.ws.base.parent.ws.base.parent
			; circular references will cause the Element.__Get.this.Clone() to fail
			; There is no need to increase the reference count for ParentAddress
			; because its lifetime is with the class Page
			; Pass this.Event to cover the WebSocket's internal event dispatcher
			ws := {"base": this.WebSocket, "_Event": this.Event, "ParentAddress": &this}
			this.ws := new ws(WsUrl)
			
			; The timeout here is perhaps duplicated with the previous line
			StartTime := A_TickCount
			while !this.Connected
			{
				if (A_TickCount-StartTime > Timeout*1000)
					throw Exception("Page connection timeout")
				else
					Sleep 50
			}
			
			; Target Domain need
			RegExMatch(WsUrl, "page/(.+)", TargetId)
			this.TargetId := TargetId1
			
			; DOM Domain need
			this.UpdateRoot()
		}
		
		/*
			Calls the specified endpoint and provides it with the given
			parameters.
			
			DomainAndMethod - The endpoint domain and method name for the
				endpoint you would like to call. For example:
				PageInst.Call("Browser.close")
				PageInst.Call("Schema.getDomains")
			
			Params - An associative array of parameters to be provided to the
				endpoint. For example:
				PageInst.Call("Page.printToPDF", {"scale": 0.5 ; Numeric Value
					, "landscape": Chrome.JSON.True() ; Boolean Value
					, "pageRanges: "1-5, 8, 11-13"}) ; String Value
				PageInst.Call("Page.navigate", {"url": "https://autohotkey.com/"})
			
			WaitForResponse - Whether to block until a response is received from
				Chrome, which is necessary to receive a return value, or whether
				to continue on with the script without waiting for a response.
			
			Timeout - Maximum number of seconds to wait for a response.
		*/
		Call(DomainAndMethod, Params:="", WaitForResponse:=True, Timeout:=30)
		{
			if !this.Connected
				throw Exception("Not connected to tab", -1)
			
			; Avoid external calls to DOM.getDocument that destroys the internal variable this.Root
			if (DomainAndMethod="DOM.getDocument" and IsObject(this.Root))
				return this.Root
			
			if (DomainAndMethod = "DOM.getRoot")
				DomainAndMethod := "DOM.getDocument"
			
			; Use a temporary variable for Id in case more calls are made
			; before we receive a response.
			Id := this.Id += 1
			; this.responses[Id] must be created before this.ws.Send()
			; or we will get response timeout if we receive a reply very soon.
			if (WaitForResponse)
				this.responses[Id] := false
			
			this.ws.Send(Chrome.JSON.Dump({"id": Id
			, "params": Params ? Params : {}
			, "method": DomainAndMethod}))
			
			if !WaitForResponse
				return
			
			; Wait for the response
			StartTime := A_TickCount
			while !this.responses[Id]
			{
				if (A_TickCount-StartTime > Timeout*1000)
					throw Exception(DomainAndMethod " response timeout", -1)
				else
					Sleep 10
			}
			
			; Get the response, check if it's an error
			response := this.responses.Delete(Id)
			if (response.error)
				throw Exception("Chrome indicated error in response", -1, Chrome.JSON.Dump(response.error))
			
			return response.result
		}
		
		/*
			Run some JavaScript on the page. For example:
			
			PageInst.Evaluate("alert(""I can't believe it's not IE!"");")
			PageInst.Evaluate("document.getElementsByTagName('button')[0].click();")
		*/
		Evaluate(JS, Timeout:=30)
		{
			try
			{
				; You can see the parameters of Runtime.evaluate in the protocol monitor
				; after pressing Enter in the chrome devtools - console.
				; Missing parameter “uniqueContextId”.
				response := this.Call("Runtime.evaluate",
				(LTrim Join
				{
					"allowUnsafeEvalBlockedByCSP": Chrome.JSON.False,
					"awaitPromise": Chrome.JSON.False,
					"expression": JS,
					"generatePreview": Chrome.JSON.True,
					"includeCommandLineAPI": Chrome.JSON.True,
					"objectGroup": "console",
					"replMode": Chrome.JSON.True,
					"returnByValue": Chrome.JSON.False,
					"silent": Chrome.JSON.False,
					"userGesture": Chrome.JSON.True
				}
				), , Timeout)
				
				if (response.exceptionDetails)
					throw Exception(response.result.description
						, -1
						, Chrome.JSON.Dump({"Code": JS, "exceptionDetails": response.exceptionDetails}))
				
				return response.result
			}
			catch e
				throw Exception(e.Message, -1)
		}
		
		/*
			Waits for the page's readyState to match the DesiredState.
			
			DesiredState - The state to wait for the page's ReadyState to match
			Interval     - How often it should check whether the state matches
			Timeout      - Maximum number of seconds to wait for the page's ReadyState to match
		*/
		WaitForLoad(DesiredState:="complete", Interval:=100, Timeout:=30)
		{
			try
			{
				StartTime := A_TickCount
				while this.Evaluate("document.readyState").value != DesiredState
				{
					if (A_TickCount-StartTime > Timeout*1000)
						throw Exception("Wait for page " DesiredState " timeout", -1)
					else
						Sleep Interval
				}
			}
			catch e
				throw Exception(e.Message, -1)
		}
		
		/*
			Internal function triggered when the script receives a message on
			the WebSocket connected to the page.
		*/
		Event(EventName, Event)
		{
			; If it was called from the WebSocket adjust the class context
			if this.ParentAddress
				this := Object(this.ParentAddress)
			
			if (EventName == "Error")
			{
				throw Exception("Error: " Event.code, -1)
			}
			else if (EventName == "Open")
			{
				this.Connected := True
				BoundKeepAlive := this.BoundKeepAlive
				SetTimer %BoundKeepAlive%, 15000
			}
			else if (EventName == "Message")
			{
				data := Chrome.JSON.Load(Event.data)
				
				; It's a response for the request of Page.Call()
				if (data.Id && this.responses.HasKey(data.Id))
					this.responses[data.Id] := data
				
				; It's CDP events
				if (data.method)
				{
					; Run the callback routine
					FnCallback := this.FnCallback
					if (newData := %fnCallback%(data))
						data := newData
					
					; Auto update root DOM node when page has been totally updated
					if (data.method == "DOM.documentUpdated")
						this.UpdateRoot()
				}
			}
			else if (EventName == "Close")
			{
				this.Disconnect()
				
				FnClose := this.FnClose
				%FnClose%(this)
			}
		}
		
		/*
			Close the page and disconnect from the page's debug interface,
			allowing the instance to be garbage collected.
			
			This method fire Page.Disconnect() automatically, so you don't
			need to call Page.Disconnect() manually.
		*/
		Close()
		{
			this.Call("Page.close")
		}
		
		/*
			Disconnect from the page's debug interface, allowing the instance
			to be garbage collected.
			
			This method should always be called when you are finished with a
			page or else your script will leak memory.
			
			Page.Call("Browser.close") or Page.Call("Page.close") or manually
			closing the page will automatically fire this method.
			
			When this method is automatically fired, DO NOT call it again
			or you will miss the event FnClose and FnCallback.
		*/
		Disconnect()
		{
			if !this.Connected
				return
			
			this.Connected := False
			this.ws := ""
			
			BoundKeepAlive := this.BoundKeepAlive
			SetTimer %BoundKeepAlive%, Delete
			this.Delete("BoundKeepAlive")
		}
		
		; https://www.dezlearn.com/nested-iframes-example/
		SwitchToMainPage()
		{
			return this.NodeId := this.Root.root.nodeId
		}
		SwitchToFrame(Index*)
		{
			try
			{
				FrameTree := this.Call("Page.getFrameTree").frameTree
				
				loop % Index.Length()
				{
					i := Index[A_Index]
					
					if (A_Index = Index.Length())
						FrameId := FrameTree.childFrames[i].frame.id
					else
						FrameTree := FrameTree.childFrames[i]
				}
				
				if (FrameId)
					return this.NodeId := this._FrameIdToNodeId(FrameId)
			}
			catch e
				throw Exception(e.Message, -1, e.Extra)
		}
		SwitchToFrameByURL(URL, MatchMode:="startswith")
		{
			return this.NodeId := this._SwitchToFrameBy("URL", URL, MatchMode)
		}
		SwitchToFrameByName(Name, MatchMode:="startswith")
		{
			return this.NodeId := this._SwitchToFrameBy("Name", Name, MatchMode)
		}
		_SwitchToFrameBy(Key, Value, MatchMode)
		{
			try
			{
				FrameTree := this.Call("Page.getFrameTree").frameTree
				FrameId := this._FindFrameBy(Key, Value, FrameTree, MatchMode)
				
				if (FrameId)
					return this._FrameIdToNodeId(FrameId)
			}
			catch e
				throw Exception(e.Message, -2, e.Extra)
		}
		_FindFrameBy(Key, Value, FrameTree, MatchMode)
		{
			for i, v in FrameTree.childFrames
			{
				if (Key = "URL")
					str := v.frame.url v.frame.urlFragment
				else if (Key = "Name")
					str := v.frame.name
				else
					return
				
				if (str = "")
					continue
				
				if ( (MatchMode = "exact"      && str = Value)            ; Case insensitive
					or (MatchMode = "contains"   && InStr(str, Value))
					or (MatchMode = "startswith" && InStr(str, Value) == 1)
					or (MatchMode = "regex"      && str ~= Value) )
					return v.frame.id
			}
			
			for i, v in FrameTree.childFrames
			{
				if (v.HasKey("childFrames"))
					ret := this._FindFrameBy(Key, Value, v, MatchMode)
				if (ret != "")
					return ret
			}
		}
		; https://github.com/Xeo786/Rufaydium-Webdriver/blob/main/CDP.ahk
		_FrameIdToNodeId(FrameId)
		{
			; 看起来 DOM.getFrameOwner 好像就直接将 FrameId 转为 NodeId 了
			; 实际上必须进行下面4步转换才能得到正确的 NodeId
			; 这个结论是试出来的，具体原理未知
			nodeId            := this.Call("DOM.getFrameOwner", {"frameId": FrameId}).nodeId
			backendNodeId     := this.Call("DOM.describeNode", {"nodeId": nodeId}).node.contentDocument.backendNodeId
			contentDocObject  := this.Call("DOM.resolveNode", {"backendNodeId": backendNodeId}).object.objectId
			return               this.Call("DOM.requestNode", {"objectId": contentDocObject}).nodeId
		}
		
		UpdateRoot()
		{
			static _i := 0
			
			try
			{
				i := _i += 1
				; DOM.getDocument 是全局生效的，每次调用后都会破坏之前已经找到的页面元素
				; 因此 Page.Call() 中做了特殊处理，可防止外部调用 DOM.getDocument
				; 所以必须使用一个内部别名 DOM.getRoot 来调用 DOM.getDocument
				; DOM.getRoot is an internal alias of DOM.getDocument
				Root := this.Call("DOM.getRoot")
				; 页面自动刷新时 DOM.documentUpdated 事件会激活至少2次
				; 每次 DOM.documentUpdated 事件又会自动调用 UpdateRoot()
				; 此时就很容易出现数个 Page.Call("DOM.getRoot") 都在等待返回值
				; 当返回值出现后，后调用的返回值将先写入 Page.NodeId
				; 而后先调用的返回值又再次写入 Page.NodeId
				; 这就会造成错误，因为先调用的返回值已经过时了
				; 所以这里将对返回值的调用顺序进行验证，只保留最后一次调用的
				; Keep only the return value of the last call to Page.Call("DOM.getRoot")
				if (i >= _i)
				{
					this.Root   := Root
					this.NodeId := this.Root.root.nodeId
				}
			}
			catch e
				throw Exception(e.Message, -1, e.Extra)
		}
		
		QuerySelector(Selector)
		{
			try NodeId := this.Call("DOM.querySelector", {"nodeId": this.NodeId, "selector": Selector}).nodeId
			return (!NodeId) ? "" : new this.Element(NodeId, this)
		}
		QuerySelectorAll(Selector)
		{
			try NodeId := this.Call("DOM.querySelectorAll", {"nodeId": this.NodeId, "selector": Selector}).nodeIds
			return (!NodeId) ? "" : new this.Element(NodeId, this)
		}
		GetElementById(Id)
		{
			return this.querySelector("[id='" Id "']")
		}
		GetElementsbyClassName(Class)
		{
			return this.querySelectorAll("[class='" Class "']")
		}
		GetElementsbyName(Name)
		{
			return this.querySelectorAll("[name='" Name "']")
		}
		GetElementsbyTagName(TagName)
		{
			return this.querySelectorAll(TagName)
		}
		; Not yet realized
		GetElementsbyXpath(Xpath)
		{
			return
		}
		
		Url[]
		{
			get
			{
				try
				{
					loop 3
						if (url := this.Evaluate("window.location.href;", Timeout := 2).value)
							return url
				}
				catch e
					throw Exception(e.Message, -1, e.Extra)
			}
			
			set
			{
				try
					this.Call("Page.navigate", {"url": value})
				catch e
					throw Exception(e.Message, -1, e.Extra)
			}
		}
		
		class Element
		{
			__New(NodeId, Parent)
			{
				ObjRawSet(this, "NodeId", NodeId)
				ObjRawSet(this, "Parent", Parent)
			}
			
			__Get(Key)
			{
				; The user wants to get a value like element[1] and NodeId is NodeIds like [1,2,3]
				if Key is digit
				{
					if (Key!="" and IsObject(this.NodeId))
					{
						if (Key = 0)
							throw Exception("Array index start at 1 instead of 0", -1)
						
						ThisClone := ObjClone(this)
						ThisClone.NodeId := this.NodeId[Key]
						return ThisClone
					}
				}
				; The user wants to get a value like element.textContent
				else
				{
					try
					{
						str := this._GetProp(Key).result.value
						
						if (SubStr(str, 1, 1)="{" and SubStr(str, 0, 1)="}")
							obj := Chrome.JSON.Load(str)
						
						return IsObject(obj) ? obj : str
					}
					catch e
						throw Exception(e.Message, -1, e.Extra)
				}
			}
			
			__Set(Key, Value)
			{
				try
					return this._SetProp(Key, Value)
				catch e
					throw Exception(e.Message, -1, e.Extra)
			}
			
			__Call(Name, Params*)
			{
				; The user wants to call a method which not in this class
				if (!IsFunc(ObjGetBase(this)[Name]))
				{
					try
					{
						str := this._CallMethod(Name, Params*).result.value
						
						if (SubStr(str, 1, 1)="{" and SubStr(str, 0, 1)="}")
							obj := Chrome.JSON.Load(str)
						
						return IsObject(obj) ? obj : str
					}
					catch e
						throw Exception(e.Message, -1, e.Extra)
				}
			}
			
			__Delete()
			{
				; MsgBox 元素释放了
			}
			
			_GetProp(Key)
			{
				JS =
				(LTrim
					function() {
						let result = this.%Key%
						if (typeof result === 'object' && result !== null) {
							return JSON.stringify(result)
						} else { return result }}
				)
				
				return this._CallFunctionOn(JS)
			}
			
			_SetProp(Key, Value)
			{
				; Escape ` to \`
				Value := StrReplace(Value, "``", "\``")
				; Escape $ to \$
				Value := StrReplace(Value, "$", "\$")
				
				JS =
				(LTrim
					function() { 
						let template = ``%Value%``;
						this.%Key% = template }
				)
				
				return this._CallFunctionOn(JS)
			}
			
			_CallMethod(Name, Params*)
			{
				for Key, Value in Params
				{
					; Escape ` to \`
					Value := StrReplace(Value, "``", "\``")
					; Escape $ to \$
					Value := StrReplace(Value, "$", "\$")
					; Build a string like
					; let param_1 = `123`;
					; let param_2 = `test`;
					StrParams1 .= Format("let param_{} = ``{}``;`n", A_Index, Value)
					; Build a string like
					; param_1,param_2,param_3
					StrParams2 .= (A_Index = 1) ? "param_1" : Format(",param_{}", A_Index)
				}
				
				JS =
				(LTrim
					function() {
						%StrParams1%
						let result = this.%Name%(%StrParams2%)
						if (typeof result === 'object' && result !== null) {
							return JSON.stringify(result)
						} else { return result }}
				)
				
				return this._CallFunctionOn(JS)
			}
			
			_CallFunctionOn(JS)
			{
				objectId := this.Parent.Call("DOM.resolveNode", {"nodeId": this.NodeId}).object.objectId
				return this.Parent.Call("Runtime.callFunctionOn", {"objectId": objectId, "functionDeclaration": JS})
			}
			
			; Return the number of elements which found by QuerySelectorAll()
			Count()
			{
				return this.NodeId.Length()
			}
			
			; Return a screenshot of the element (base64 encoded),
			; you can save it as an image file by using the ImagePut library.
			; https://github.com/iseahound/ImagePut
			Screenshot()
			{
				try
				{
					JS =
					(LTrim
						function() {
							const e = this.getBoundingClientRect(),
							t = this.ownerDocument.documentElement.getBoundingClientRect();
							return JSON.stringify({
								x: e.left - t.left,
								y: e.top - t.top,
								width: e.width,
								height: e.height,
								scale: 1})}
					)
					
					params := { "captureBeyondViewport": Chrome.JSON.True
										, "clip": Chrome.JSON.Load(this._CallFunctionOn(JS).result.value)
										, "format": "png"
										, "fromSurface": Chrome.JSON.True
										, "quality": 100}
					
					return this.Parent.Call("Page.captureScreenshot", params).data
				}
				catch e
					throw Exception(e.Message, -1, e.Extra)
			}
		}
		
		class WebSocket {
			
			; The primary HINTERNET handle to the websocket connection
			; This field should not be set externally.
			ptr := ""
			
			; Whether the websocket is operating in Synchronous or Asynchronous mode.
			; This field should not be set externally.
			async := ""
			
			; The readiness state of the websocket.
			; This field should not be set externally.
			readyState := 0
			
			; The URL this websocket is connected to
			; This field should not be set externally.
			url := ""
			
			; Internal array of HINTERNET handles
			HINTERNETs := []
			
			; Internal buffer used to receive incoming data
			cache := "" ; Access ONLY by ObjGetAddress
			cacheSize := 8192
			
			; Internal buffer used to hold data fragments for multi-packet messages
			recData := ""
			recDataSize := 0
			
			; Define in winerror.h
			ERROR_INVALID_OPERATION := 4317
			
			; Aborted connection Event
			EVENT_ABORTED := { status: 1006 ; WEB_SOCKET_ABORTED_CLOSE_STATUS
				, reason: "The connection was closed without sending or receiving a close frame." }
			
			_LastError(Err := -1)
			{
				static module := DllCall("GetModuleHandle", "Str", "winhttp", "Ptr")
				Err := Err < 0 ? A_LastError : Err
				hMem := ""
				DllCall("Kernel32.dll\FormatMessage"
				, "Int", 0x1100 ; [in]           DWORD   dwFlags
				, "Ptr", module ; [in, optional] LPCVOID lpSource
				, "Int", Err    ; [in]           DWORD   dwMessageId
				, "Int", 0      ; [in]           DWORD   dwLanguageId
				, "Ptr*", hMem  ; [out]          LPTSTR  lpBuffer
				, "Int", 0      ; [in]           DWORD   nSize
				, "Ptr", 0      ; [in, optional] va_list *Arguments
				, "UInt") ; DWORD
				return StrGet(hMem), DllCall("Kernel32.dll\LocalFree", "Ptr", hMem, "Ptr")
			}
			
			; Internal function used to load the mcode event filter
			_StatusSyncCallback()
			{
				if this.pCode
					return this.pCode
				b64 := (A_PtrSize == 4)
				? "i1QkDIPsDIH6AAAIAHQIgfoAAAAEdTWLTCQUiwGJBCSLRCQQiUQkBItEJByJRCQIM8CB+gAACAAPlMBQjUQkBFD/cQyLQQj/cQT/0IPEDMIUAA=="
				: "SIPsSEyL0kGB+AAACAB0CUGB+AAAAAR1MEiLAotSGEyJTCQwRTPJQYH4AAAIAEiJTCQoSYtKCEyNRCQgQQ+UwUiJRCQgQf9SEEiDxEjD"
				if !DllCall("crypt32\CryptStringToBinary", "Str", b64, "UInt", 0, "UInt", 1, "Ptr", 0, "UInt*", s := 0, "Ptr", 0, "Ptr", 0)
					throw Exception("failed to parse b64 to binary")
				ObjSetCapacity(this, "code", s)
				this.pCode := ObjGetAddress(this, "code")
				if !DllCall("crypt32\CryptStringToBinary", "Str", b64, "UInt", 0, "UInt", 1, "Ptr", this.pCode, "UInt*", s, "Ptr", 0, "Ptr", 0) &&
					throw Exception("failed to convert b64 to binary")
				if !DllCall("VirtualProtect", "Ptr", this.pCode, "UInt", s, "UInt", 0x40, "UInt*", 0)
					throw Exception("failed to mark memory as executable")
				return this.pCode
				/* c++ source
					struct __CONTEXT {
						void *obj;
						HWND hwnd;
						decltype(&SendMessageW) pSendMessage;
						UINT msg;
					};
					void __stdcall WinhttpStatusCallback(
					void *hInternet,
					DWORD_PTR dwContext,
					DWORD dwInternetStatus,
					void *lpvStatusInformation,
					DWORD dwStatusInformationLength) {
						if (dwInternetStatus == 0x80000 || dwInternetStatus == 0x4000000) {
							__CONTEXT *context = (__CONTEXT *)dwContext;
							void *param[3] = { context->obj,hInternet,lpvStatusInformation };
							context->pSendMessage(context->hwnd, context->msg, (WPARAM)param, dwInternetStatus == 0x80000);
						}
					}
				*/
			}
			
			; Internal event dispatcher for compatibility with the legacy interface
			_Event(name, event)
			{
				this["On" name](event)
			}
			
			; Reconnect
			reconnect()
			{
				this.connect()
			}
			
			pRecData[] {
				get {
					return ObjGetAddress(this, "recData")
				}
			}
			
			__New(url, events := 0, async := true, headers := "")
			{
				this.url := url
				
				this.HINTERNETs := []
				
				; Force async to boolean
				this.async := async := !!async
				
				; Initialize the Cache
				ObjSetCapacity(this, "cache", this.cacheSize)
				this.pCache := ObjGetAddress(this, "cache")
				
				; Initialize the RecData
				; this.pRecData := ObjGetAddress(this, "recData")
				
				; script's built-in window for message targeting
				this.hWnd := A_ScriptHwnd
				
				; Parse the url
				if !RegExMatch(url, "Oi)^((?<SCHEME>wss?)://)?((?<USERNAME>[^:]+):(?<PASSWORD>.+)@)?(?<HOST>[^/:]+)(:(?<PORT>\d+))?(?<PATH>/.*)?$", m)
					throw Exception("Invalid websocket url")
				this.m := m
				
				; Open a new HTTP API instance
				if !(hSession := DllCall("Winhttp\WinHttpOpen"
					, "Ptr", 0  ; [in, optional]        LPCWSTR pszAgentW
					, "UInt", 0 ; [in]                  DWORD   dwAccessType
					, "Ptr", 0  ; [in]                  LPCWSTR pszProxyW
					, "Ptr", 0  ; [in]                  LPCWSTR pszProxyBypassW
					, "UInt", async * 0x10000000 ; [in] DWORD   dwFlags
					, "Ptr")) ; HINTERNET
					throw Exception("WinHttpOpen failed: " this._LastError())
				this.HINTERNETs.Push(hSession)
				
				; Connect the HTTP API to the remote host
				port := m.PORT ? (m.PORT + 0) : (m.SCHEME = "ws") ? 80 : 443
				if !(this.hConnect := DllCall("Winhttp\WinHttpConnect"
					, "Ptr", hSession ; [in] HINTERNET     hSession
					, "WStr", m.HOST  ; [in] LPCWSTR       pswzServerName
					, "UShort", port  ; [in] INTERNET_PORT nServerPort
					, "UInt", 0       ; [in] DWORD         dwReserved
					, "Ptr")) ; HINTERNET
					throw Exception("WinHttpConnect failed: " this._LastError())
				this.HINTERNETs.Push(this.hConnect)
				
				; Translate headers from array to string
				if IsObject(headers)
				{
					s := ""
					for k, v in headers
						s .= "`r`n" k ": " v
					headers := LTrim(s, "`r`n")
				}
				this.headers := headers
				
				; Set any event handlers from events parameter
				for k, v in IsObject(events) ? events : []
					if (k ~= "i)^(data|message|close|error|open)$")
						this["on" k] := v
				
				; Set up a handler for messages from the StatusSyncCallback mcode
				this.wm_ahkmsg := DllCall("RegisterWindowMessage", "Str", "AHK_WEBSOCKET_STATUSCHANGE_" &this, "UInt")
				; .Bind({}) make parameter "this" = {}
				OnMessage(this.wm_ahkmsg, this.WEBSOCKET_STATUSCHANGE.Bind({})) ; TODO: Proper binding
				
				; Connect on start
				this.connect()
			}
			
			connect() {
				; Collect pointer to SendMessageW routine for the StatusSyncCallback mcode
				static pSendMessageW := DllCall("GetProcAddress", "Ptr", DllCall("GetModuleHandle", "Str", "User32", "Ptr"), "AStr", "SendMessageW", "Ptr")
				
				; If the HTTP connection is closed, we cannot request a websocket
				if !this.HINTERNETs.Length()
					throw Exception("The connection is closed")
				
				; Shutdown any existing websocket connection
				this.shutdown()
				
				; Free any HINTERNET handles from previous websocket connections
				while (this.HINTERNETs.Length() > 2)
					DllCall("Winhttp\WinHttpCloseHandle", "Ptr", this.HINTERNETs.Pop())
				
				; Open an HTTP Request for the target path
				dwFlags := (this.m.SCHEME = "wss") ? 0x800000 : 0
				if !(hRequest := DllCall("Winhttp\WinHttpOpenRequest"
					, "Ptr", this.hConnect ; [in] HINTERNET hConnect,
					, "WStr", "GET"        ; [in] LPCWSTR   pwszVerb,
					, "WStr", this.m.PATH  ; [in] LPCWSTR   pwszObjectName,
					, "Ptr", 0             ; [in] LPCWSTR   pwszVersion,
					, "Ptr", 0             ; [in] LPCWSTR   pwszReferrer,
					, "Ptr", 0             ; [in] LPCWSTR   *ppwszAcceptTypes,
					, "UInt", dwFlags      ; [in] DWORD     dwFlags
					, "Ptr")) ; HINTERNET
					throw Exception("WinHttpOpenRequest failed: " this._LastError())
				this.HINTERNETs.Push(hRequest)
				
				if this.headers
				{
					if ! DllCall("Winhttp\WinHttpAddRequestHeaders"
						, "Ptr", hRequest      ; [in] HINTERNET hRequest,
						, "WStr", this.headers ; [in] LPCWSTR   lpszHeaders,
						, "UInt", -1           ; [in] DWORD     dwHeadersLength,
						, "UInt", 0x20000000   ; [in] DWORD     dwModifiers
						, "Int") ; BOOL
						throw Exception("WinHttpAddRequestHeaders failed: " this._LastError())
				}
				
				; Make the HTTP Request
				status := "00000"
				if (!DllCall("Winhttp\WinHttpSetOption", "Ptr", hRequest, "UInt", 114, "Ptr", 0, "UInt", 0, "Int")
					|| !DllCall("Winhttp\WinHttpSendRequest", "Ptr", hRequest, "Ptr", 0, "UInt", 0, "Ptr", 0, "UInt", 0, "UInt", 0, "UPtr", 0, "Int")
					|| !DllCall("Winhttp\WinHttpReceiveResponse", "Ptr", hRequest, "Ptr", 0)
					|| !DllCall("Winhttp\WinHttpQueryHeaders", "Ptr", hRequest, "UInt", 19, "Ptr", 0, "WStr", status, "UInt*", 10, "Ptr", 0, "Int")
					|| status != "101")
					throw Exception("Invalid status: " status)
				
				; Upgrade the HTTP Request to a Websocket connection
				if !(this.ptr := DllCall("Winhttp\WinHttpWebSocketCompleteUpgrade", "Ptr", hRequest, "Ptr", 0))
					throw Exception("WinHttpWebSocketCompleteUpgrade failed: " this._LastError())
				
				; Close the HTTP Request, save the Websocket connection
				DllCall("Winhttp\WinHttpCloseHandle", "Ptr", this.HINTERNETs.Pop())
				this.HINTERNETs.Push(this.ptr)
				this.readyState := 1
				
				; Configure asynchronous callbacks
				if (this.async)
				{
					; Populate context struct for the mcode to reference
					ObjSetCapacity(this, "__context", 4 * A_PtrSize)
					pCtx := ObjGetAddress(this, "__context")
					NumPut(&this         , pCtx + A_PtrSize * 0, "Ptr")
					NumPut(this.hWnd     , pCtx + A_PtrSize * 1, "Ptr")
					NumPut(pSendMessageW , pCtx + A_PtrSize * 2, "Ptr")
					NumPut(this.wm_ahkmsg, pCtx + A_PtrSize * 3, "UInt")
					
					if !DllCall("Winhttp\WinHttpSetOption"
						, "Ptr", this.ptr   ; [in] HINTERNET hInternet
						, "UInt", 45        ; [in] DWORD     dwOption
						, "Ptr*", pCtx      ; [in] LPVOID    lpBuffer
						, "UInt", A_PtrSize ; [in] DWORD     dwBufferLength
						, "Int") ; BOOL
						throw Exception("WinHttpSetOption failed: " this._LastError())
					
					StatusCallback := this._StatusSyncCallback()
					if (-1 == DllCall("Winhttp\WinHttpSetStatusCallback"
						, "Ptr", this.ptr       ; [in] HINTERNET               hInternet,
						, "Ptr", StatusCallback ; [in] WINHTTP_STATUS_CALLBACK lpfnInternetCallback,
						, "UInt", 0x80000       ; [in] DWORD                   dwNotificationFlags,
						, "UPtr", 0             ; [in] DWORD_PTR               dwReserved
						, "Ptr")) ; WINHTTP_STATUS_CALLBACK
						throw Exception("WinHttpSetStatusCallback failed: " this._LastError())
					
					; Make the initial request for data to receive an asynchronous response for
					if (ret := DllCall("Winhttp\WinHttpWebSocketReceive"
						, "Ptr", this.ptr        ; [in]  HINTERNET                      hWebSocket,
						, "Ptr", this.pCache     ; [out] PVOID                          pvBuffer,
						, "UInt", this.cacheSize ; [in]  DWORD                          dwBufferLength,
						, "UInt*", 0             ; [out] DWORD                          *pdwBytesRead,
						, "UInt*", 0             ; [out] WINHTTP_WEB_SOCKET_BUFFER_TYPE *peBufferType
						, "UInt")) ; DWORD
						throw Exception("WinHttpWebSocketReceive failed: " ret)
				}
				
				; Fire the open event
				this._Event("Open", {timestamp:A_Now A_Msec, url: this.url})
			}
			
			WEBSOCKET_STATUSCHANGE(wp, lp, msg, hwnd) {
				; Buffer events
				Critical
				
				; Grab `this` from the provided context struct
				this := Object(NumGet(wp + A_PtrSize * 0, "Ptr"))
				
				if !lp {
					this.readyState := 3
					return
				}
				
				; Don't process data when the websocket isn't ready
				if (this.readyState != 1)
					return
				
				; Grab the rest of the context data
				hInternet :=            NumGet(wp + A_PtrSize * 1, "Ptr")
				lpvStatusInformation := NumGet(wp + A_PtrSize * 2, "Ptr")
				dwBytesTransferred :=   NumGet(lpvStatusInformation + 0, "UInt")
				eBufferType :=          NumGet(lpvStatusInformation + 4, "UInt")
				
				; Mark the current size of the received data buffer for use as an offset
				; for the start of any newly provided data
				offset := this.recDataSize
				
				if (eBufferType > 3)
				{
					closeStatus := this.QueryCloseStatus()
					this.shutdown()
					; We need to return as soon as possible.
					; If we don't use a SetTimer and call a ws request in Close event, it will cause a deadlock.
					BoundFunc := this._Event.Bind(this, "Close", {reason: closeStatus.reason, status: closeStatus.status})
					SetTimer %BoundFunc%, -1
					return
				}
				
				try {
					if (eBufferType == 0) ; BINARY
					{
						if offset ; Continued from a fragment
						{
							VarSetCapacity(data, offset + dwBytesTransferred)
							
							; Copy data from the fragment buffer
							DllCall("RtlMoveMemory"
							, "Ptr", &data
							, "Ptr", this.pRecData
							, "UInt", this.recDataSize)
							
							; Copy data from the new data cache
							DllCall("RtlMoveMemory"
							, "Ptr", &data + offset
							, "Ptr", this.pCache
							, "UInt", dwBytesTransferred)
							
							; Clear fragment buffer
							this.recDataSize := 0
							
							; We need to return as soon as possible.
							; If we don't use a SetTimer and call a ws request in Data event, it will cause a deadlock.
							BoundFunc := this._Event.Bind(this, "Data", {data: &data, size: offset + dwBytesTransferred})
							SetTimer %BoundFunc%, -1
						}
						else ; No prior fragment
						{
							; Copy data from the new data cache
							VarSetCapacity(data, dwBytesTransferred)
							
							DllCall("RtlMoveMemory"
							, "Ptr", &data
							, "Ptr", this.pCache
							, "UInt", dwBytesTransferred)
							
							; We need to return as soon as possible.
							; If we don't use a SetTimer and call a ws request in Data event, it will cause a deadlock.
							BoundFunc := this._Event.Bind(this, "Data", {data: &data, size: dwBytesTransferred})
							SetTimer %BoundFunc%, -1
						}
					}
					else if (eBufferType == 2) ; UTF8
					{
						if offset ; Continued from a fragment
						{
							this.recDataSize += dwBytesTransferred
							ObjSetCapacity(this, "recData", this.recDataSize)
							
							DllCall("RtlMoveMemory"
							, "Ptr", this.pRecData + offset
							, "Ptr", this.pCache
							, "UInt", dwBytesTransferred)
							
							msg := StrGet(this.pRecData, "utf-8")
							this.recDataSize := 0
						}
						else ; No prior fragment
							msg := StrGet(this.pCache, dwBytesTransferred, "utf-8")
						
						; We need to return as soon as possible.
						; If we don't use a SetTimer and call a ws request in Message event, it will cause a deadlock.
						BoundFunc := this._Event.Bind(this, "Message", {data: msg})
						SetTimer %BoundFunc%, -1
					}
					else if (eBufferType == 1 || eBufferType == 3) ; BINARY_FRAGMENT, UTF8_FRAGMENT
					{
						; Add the fragment to the received data buffer
						this.recDataSize += dwBytesTransferred
						ObjSetCapacity(this, "recData", this.recDataSize)
						DllCall("RtlMoveMemory"
						, "Ptr", this.pRecData + offset
						, "Ptr", this.pCache
						, "UInt", dwBytesTransferred)
					}
				}
				finally
				{
					askForMoreData := this.askForMoreData.Bind(this, hInternet)
					SetTimer %askForMoreData%, -1
				}
			}
			
			askForMoreData(hInternet)
			{
				; Original implementation used a while loop here, but in my experience
				; that causes lost messages
				ret := DllCall("Winhttp\WinHttpWebSocketReceive"
				, "Ptr", hInternet       ; [in]  HINTERNET hWebSocket,
				, "Ptr", this.pCache     ; [out] PVOID     pvBuffer,
				, "UInt", this.cacheSize ; [in]  DWORD     dwBufferLength,
				, "UInt*", 0             ; [out] DWORD     *pdwBytesRead,
				, "UInt*", 0             ; [out]           *peBufferType
				, "UInt") ; DWORD
				if (ret && ret != this.ERROR_INVALID_OPERATION)
					this._Error({code: ret})
			}
			
			__Delete()
			{
				this.shutdown()
				; Free all active HINTERNETs
				while (this.HINTERNETs.Length())
					DllCall("Winhttp\WinHttpCloseHandle", "Ptr", this.HINTERNETs.Pop())
			}
			
			; Default error handler
			_Error(err)
			{
				if (err.code != 12030) {
					this._Event("Error", {code: ret})
					return
				}
				if (this.readyState == 3)
					return
				this.readyState := 3
				try this._Event("Close", this.EVENT_ABORTED)
			}
			
			queryCloseStatus() {
				usStatus := 0
				VarSetCapacity(vReason, 123, 0)
				if (!DllCall("Winhttp\WinHttpWebSocketQueryCloseStatus"
					, "Ptr", this.ptr     ; [in]  HINTERNET hWebSocket,
					, "UShort*", usStatus ; [out] USHORT    *pusStatus,
					, "Ptr", &vReason     ; [out] PVOID     pvReason,
					, "UInt", 123         ; [in]  DWORD     dwReasonLength,
					, "UInt*", len        ; [out] DWORD     *pdwReasonLengthConsumed
					, "UInt")) ; DWORD
					return { status: usStatus, reason: StrGet(&vReason, len, "utf-8") }
				else if (this.readyState > 1)
					return this.EVENT_ABORTED
			}
			
			; eBufferType BINARY_MESSAGE = 0, BINARY_FRAGMENT = 1, UTF8_MESSAGE = 2, UTF8_FRAGMENT = 3
			sendRaw(eBufferType, pvBuffer, dwBufferLength) {
				if (this.readyState != 1)
					throw Exception("websocket is disconnected")
				if (ret := DllCall("Winhttp\WinHttpWebSocketSend"
					, "Ptr", this.ptr        ; [in] HINTERNET                      hWebSocket
					, "UInt", eBufferType    ; [in] WINHTTP_WEB_SOCKET_BUFFER_TYPE eBufferType
					, "Ptr", pvBuffer        ; [in] PVOID                          pvBuffer
					, "UInt", dwBufferLength ; [in] DWORD                          dwBufferLength
					, "UInt")) ; DWORD
					this._Error({code: ret})
			}
			
			; sends a utf-8 string to the server
			send(str)
			{
				if (size := StrPut(str, "utf-8") - 1)
				{
					VarSetCapacity(buf, size, 0)
					StrPut(str, &buf, "utf-8")
					this.sendRaw(2, &buf, size)
				}
				else
					this.sendRaw(2, 0, 0)
			}
			
			receive()
			{
				if (this.async)
					throw Exception("Used only in synchronous mode")
				if (this.readyState != 1)
					throw Exception("websocket is disconnected")
				
				rec := {data: "", size: 0, ptr: 0}
				
				offset := 0
				while (!ret := DllCall("Winhttp\WinHttpWebSocketReceive"
					, "Ptr", this.ptr           ; [in]  HINTERNET                      hWebSocket
					, "Ptr", this.pCache        ; [out] PVOID                          pvBuffer
					, "UInt", this.cacheSize    ; [in]  DWORD                          dwBufferLength
					, "UInt*", dwBytesRead := 0 ; [out] DWORD                          *pdwBytesRead
					, "UInt*", eBufferType := 0 ; [out] WINHTTP_WEB_SOCKET_BUFFER_TYPE *peBufferType
					, "UInt")) ; DWORD
				{
					switch eBufferType
					{
						case 0:
						if offset
						{
							rec.size += dwBytesRead
							ObjSetCapacity(rec, "data", rec.size)
							ptr := ObjGetAddress(rec, "data")
							DllCall("RtlMoveMemory", "Ptr", ptr + offset, "Ptr", this.pCache, "UInt", dwBytesRead)
						}
						else
						{
							rec.Size := dwBytesRead
							ObjSetCapacity(rec, "data", rec.size)
							ptr := ObjGetAddress(rec, "data")
							DllCall("RtlMoveMemory", "Ptr", ptr, "Ptr", this.pCache, "UInt", dwBytesRead)
						}
						return rec
						case 1, 3:
						rec.size += dwBytesRead
						ObjSetCapacity(rec, "data", rec.size)
						ptr := ObjGetAddress(rec, "data")
						DllCall("RtlMoveMemory", "Ptr", rec + offset, "Ptr", this.pCache, "UInt", dwBytesRead)
						offset += dwBytesRead
						case 2:
						if (offset) {
							rec.size += dwBytesRead
							ObjSetCapacity(rec, "data", rec.size)
							ptr := ObjGetAddress(rec, "data")
							DllCall("RtlMoveMemory", "Ptr", ptr + offset, "Ptr", this.pCache, "UInt", dwBytesRead)
							return StrGet(ptr, "utf-8")
						}
						return StrGet(this.pCache, dwBytesRead, "utf-8")
						default:
						rea := this.queryCloseStatus()
						this.shutdown()
						try this._Event("Close", {status: rea.status, reason: rea.reason})
							return
					}
				}
				if (ret && ret != this.ERROR_INVALID_OPERATION)
					this._Error({code: ret})
			}
			
			; sends a close frame to the server to close the send channel, but leaves the receive channel open.
			shutdown() {
				if (this.readyState != 1)
					return
				this.readyState := 2
				DllCall("Winhttp\WinHttpWebSocketShutdown", "Ptr", this.ptr, "UShort", 1000, "Ptr", 0, "UInt", 0)
				this.readyState := 3
			}
		}
	}
	
	Jxon_Load(p*)
	{
		return this.JSON.Load(p*)
	}
	
	Jxon_Dump(p*)
	{
		return this.JSON.Dump(p*)
	}
	
	Jxon_True()
	{
		return this.JSON.True()
	}
	
	Jxon_False()
	{
		return this.JSON.False()
	}
	
	Jxon_Null()
	{
		return this.JSON.Null()
	}
	
	/*
		cJson.ahk 0.6.0-git-built
		Copyright (c) 2021 Philip Taylor (known also as GeekDude, G33kDude)
		https://github.com/G33kDude/cJson.ahk
		
		MIT License
		
		Permission is hereby granted, free of charge, to any person obtaining a copy
		of this software and associated documentation files (the "Software"), to deal
		in the Software without restriction, including without limitation the rights
		to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
		copies of the Software, and to permit persons to whom the Software is
		furnished to do so, subject to the following conditions:
		
		The above copyright notice and this permission notice shall be included in all
		copies or substantial portions of the Software.
		
		THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
		IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
		FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
		AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
		LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
		OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
		SOFTWARE.
	*/
	class JSON
	{
		static version := "0.6.0-git-built"
		
		BoolsAsInts[]
		{
			get
			{
				this._init()
				return NumGet(this.lib.bBoolsAsInts, "Int")
			}
			
			set
			{
				this._init()
				NumPut(value, this.lib.bBoolsAsInts, "Int")
				return value
			}
		}
		
		NullsAsStrings[]
		{
			get
			{
				this._init()
				return NumGet(this.lib.bNullsAsStrings, "Int")
			}
			
			set
			{
				this._init()
				NumPut(value, this.lib.bNullsAsStrings, "Int")
				return value
			}
		}
		
		EmptyObjectsAsArrays[]
		{
			get
			{
				this._init()
				return NumGet(this.lib.bEmptyObjectsAsArrays, "Int")
			}
			
			set
			{
				this._init()
				NumPut(value, this.lib.bEmptyObjectsAsArrays, "Int")
				return value
			}
		}
		
		EscapeUnicode[]
		{
			get
			{
				this._init()
				return NumGet(this.lib.bEscapeUnicode, "Int")
			}
			
			set
			{
				this._init()
				NumPut(value, this.lib.bEscapeUnicode, "Int")
				return value
			}
		}
		
		_init()
		{
			if (this.lib)
				return
			this.lib := this._LoadLib()
			
			; Populate globals
			NumPut(&this.True, this.lib.objTrue, "UPtr")
			NumPut(&this.False, this.lib.objFalse, "UPtr")
			NumPut(&this.Null, this.lib.objNull, "UPtr")
			
			this.fnGetObj := Func("Object")
			NumPut(&this.fnGetObj, this.lib.fnGetObj, "UPtr")
			
			this.fnCastString := Func("Format").Bind("{}")
			NumPut(&this.fnCastString, this.lib.fnCastString, "UPtr")
		}
		
		_LoadLib32Bit() {
			static CodeBase64 := ""
			. "3bocAQADAAFwATBXVlMAg+wgixV8DAAAAIt0JDCLXCQANIt8JDiLRCQAPIsKOQ4PhIpBAJSF2w+EqgAci0gDunQADLlfAAiJAHQkGMH+H2aJAFAc"
			. "jVAgxwAiAABVAMdABG4AQmsADAhuAG8ADAwIdwBuAAwQXwBPIQAMFGIAagAMGGUAAGMAiRNmiUgAHo1EJBiJfCQACIlcJASJBCQhAFIc6OIZAWeN"
			. "UCACiRO7IgBnZokAGIPEIDHAW14AX8NmkItUJEAgD7bAifkBLvCJAlQAN9ro7w0AAIkGI422Ad+DBxAFXPDHRCQEARIDYIFZgjOieoAzgwcBhhuQ"
			. "AgABBI8AjUwkBIPkCPC6FIAF/3H8VYSJ5YCUUYHsqIGCAEEEizlmiRCJPEWUgHSBFoB0AQOLBwAPtwiNUfdmgyD6Fw+Hy4GU7P8Af/8Po9EPgkMi"
			. "AgAqWAK+AQiNdkAAD7cLidgGFZ4BABUPo9aNWwJzAOaJB2aD+VsPyISkBYAJjh0AG4AHMG4PhBiAB4AEdA8IhbADACVQAmaDAHgCcokXD4XokQDk"
			. "jVAEgAcEdYEHStiCBwaABwZlgQfIQYAHg8AIgD2CbIkgBw+E/gYAK0WUdr8AEsBXOEAxwYJEMeuAAt3YMcDpl0ERhLQmAkN2AIkfwB4Aew+FYP//"
			. "/4MAwAJmD+/AjU1CmEIziQehJMAKDwARRbyLEIlMJFAYjU28wFwgAkZERCQcAh1MJBTAAhB5ghlEJMIZwAEDT8dn/wBSGItdoIsHg3DsJOmPAR7H"
			. "H0FFOggPhfzBdsACiQchgC+JPCSJwA7oUAD+//+FwA+F4AeBYIAFwBWLRbCJHElDB6IKC2Z3IkBaD8yCjgFRwWFIAsATRWIMhmyABcIaLA+FawuB"
			. "CEMgkMIcD7cQjWpKAAr5AAp7AAeADH0ID4REQQKF0g+EAjuDBCJ1Wo1FqEkFJ7P9ASd1R8uGLzOAUYAhcjDFF8whhwwBAwhz54kH6wvdANjrB93Y"
			. "jXQmCACQuMAF/41l8IJZgKxdjWH8w0AjQC10Dw+OGwCKg0TpMIADCXfaQEG+EUGuZokwT6gYZoNA+y0PhBMHoAJFgpAhMtnox0WEwQMhIAMwD4TY"
			. "oEONUwLPABEId4SLdZQAi1YIi04MiVUQiIlNjOgha02MEAqJB7jAKwD3ZQCIAcoPv8uJywDB+x8ByBHag4DA0InDiUWIABEAg9L/iVWMiVgQCIlQ"
			. "DMIPjXPQQGaD/gl2vKANLogPhOCgDYPj34ABSEUPhYKMXZSiLWbAgzsUD4SSYEPgLkuAEWAWcIABMdtgASuAdQuNSAIPt6CEIA+JyI1KIAr5CYgP"
			. "h9cgQYl9iMAHBDHJ5IDqMI0MiQSJxkACD7/SjQwiSmAG/o164AX/CQB24ot9iIk3hRDJD4RNgCEx0rgDgSHjBo0EgIPCAUABwDnKdfTgGNuhQhnd"
			. "QAiEIKGQIBYQ3vHdWKBMlA+3FYAm+OAU5sJz+AUPIIW+/P//IAPcSFYIQAQAaU6AEpDgE2ZYD4U+QAEkd2Ehcy5r4gEid2zhAR7iASJ3c1XhAQ7i"
			. "AQjgAQgief7RgEmDwAooeUlgToAN2rsjeRirPYAP0SAGAUcd4A8iQBOgAcArjXACArrhBIk3iXMIZoCJE4sXD7cKIgQEhMQgLIPABOsfgwQ9oLT+"
			. "icaJ2gAEW8F+YgSvQR2hJm+BC1oCAmKDXHXUD7dKBSQE02JJ+S8PhG4RYAWD6VyAARkPhwI/4AUPt8n/JI3OCCC24llhcYN3ICbhPWA4fQ+FG0Ic"
			. "A3y/7gnjk4BHQBkGoQ2kEuAGkM4Pg2fgBunqgADbZCqin9riAWcqyuIBYio94gG64AGioUIkYCiF1kvAPqAiuKMNA6Fh4YkMQwiAmSGSBDHAg1Ds"
			. "BOmIwAa54dGDEMIEicbCIhfp5qvgM6ehu6uhqKWhqKSfByqiv6GioUWgx0WIY+EEQKKJRYQBaGeQ2MNHpGBiXQ+E7yEBQZEm3EShhJAu+SOkvvsB"
			. "4WOQMfaLTYhmGIl15EJCc0XNzMwAzIPuAffhicgAweoDjTySAf8AKfiDwDBmiUQAdbyJyInRg/iICXfZMAWLfZARVkaNYQGwBYtFhKAK6AY8cB7J"
			. "CXcgD6PL+A+CTQAHcx6gOvFN0wGEdjjhHvosdTcwAb6DAA66VdJRATsRBDawAE0wUOB0DjABc7PCA10QD4Xv+nICi12ERrmxGzIjZokI4yLXs8AB"
			. "UB2hhOAV0y5DYAEp0C7pvZMBvjEDoYDB4AFmiTPpC6AcQAGJggSheEIBC+n2ISdNc0a7QRjBRumOMA3fGGsIuhAPQAIT3VugCIsH6VmBDkqQITCJ"
			. "DzHJ0SHAMASNAllwRvsJdh2NWUK/gAAFD4a+UYBZEp/CAIcwcAiNWakAweMEjUoGiQ8IZolYUQMGZoldYoiUAw+GaAID1ANzJdkD8jAdD7egAkwL"
			. "gKnB4QSNWghwOFaJcR3CBwgmBBopBCNVKQSvLQQKKgQKJgTMK7GAJQQCKQRsKASDwmoMdDHO0BC7kRTEMli1QQG5QAG5cD8aNKSRAqvRGZkCj0EB"
			. "XEwBekEBu8FmSQFlMQXxMzkFUFEuAPAxyYlI/IPCIgIxHwYxwHABxfhjglkccReNQgAeUEwHDOlrwAygRNnoD7cMWAKwcbF2iRfZ4EyJ0PBxwQDp"
			. "2yAE3SLYcCKLdZCQL4tLAAwPr0MID6/OgAHBifD3YwgwJigByrjDWANAB1MMVOlPUQdNIW27ESOJiAffaTBXGd1ZYCNV0XBTMBb6sGu4wAG6QQJo"
			. "FJKD6zDwAgFi0qEg30WIoHcAaInAB9753EEIhgNkdMjQ6b4QBt7JwGYCDDS5L+wQQeEusEDxixBACCnBMksPt02giAHZ6UunAP2iWY2iAK+iACId"
			. "yenlyQBCleEwWcnpSkkBBpMxUPR7hECgCOn/QADw2ejpy2AAQ7V4tQUAADAxMjM0NTY3ADg5QUJDREVGQTEBSB4AACAwAPgAHQAA8R8AAND9cACo"
			. "tAA/AD8APwA/ADEAalgwBamQJMBwGj0AlK18AdN/AjoAvvwBf/QACmpwAFwQMGYAYQB4bABz0tGh0XHRQdFfxABWkgF1AGXyEHLYIlDQ12CNVNDX"
			. "dCSqaIBgOAIqA1DOFFAB1mRwAMHMEGRiDORj42IAHCT/UBSLA4PU7BigAkBgAURiAaADVSDTOPAATPIAdLIBSPukAx1pGJVpMQWdacLWYQYwGA+3"
			. "BuBo0I4JdAJXUAADdBGDxFADstf2uot+DIt2CAUQ2vpBL4CD0gCDUPoAdtgw2TyDuQgVEOZkwmlxoBKFwHQCvCHniTCJeATr6rFw3kb1dwjQd+QF"
			. "1iQwkJBXjZDdANr/dwGz2Yn+U4nTgewCjAETP4t2BIlNKLSLUBDasJDifahAiXWkiE2jgHGFIgzASw+2BfENiEUKrHHtdKCfgH2sAQAZyYPhIIPB"
			. "WwCLM4B9qACNRgACiQNmiQ4PhSYSAAyQA47qkpawMRD/i3AM8AIAdXyB0AA5eBgPjoDQBIWRBOCwBYsLjUGQAwq4k+sBYAyJRdjBAPgfiUXci0W0"
			. "U3LuwXNF2EFz96HJEzFShWaJCnBIwEe5OofxEhAIEfIID4TU0VagUATGRawQAboBGwUQ9wLwEQyD+AEPwoTy0PgGD4TxaeGn5IQiEZz4AqChgQtg"
			. "CUJRgQsDixWQsFdmNrsAD28FeA0AAIkAUBiNUB4PEQAg8w9+BYgAgGYPANZAEIkTul8AAQAsiVAci0W0iQBcJASJRCQIiQA0JOhNCgAAiwgDuSIA"
			. "dIPHAYkAwoPAAokDZokACotNsDl5EA8Ijn0CAKb+weYEAANxDInCjUgCAIB9owCJC4nIAGbHAiwAD4V1QAQAAIB9rAASQwD///+LVbA5egAYD4/R"
			. "/v//OWB6HA+PyABXCHGLAEYIiQQk6DgMBQJ0OgAcjVACiRMEZokAGQyD+AEPBIUJAEWNdCYAkIkFNTQkATjopQkBSAKwAKM7eBAPjToCAwWWcAyF"
			. "2w+EIQGmiwPpWoEetCYBgCsAO1AYD4Q/AAUAAMZFrAC5RnuACIAThfj9AFJFgLSDAAGAfagAWoJuABCF0g+O3oAnAQAvMf+LcAzp/VMAEoQiZpCB"
			. "LlKCLroKdAAIuYGjxwAiAAJPgaYMjVAQx0AABGIAagDHQAgQZQBjAAFmSA7pCt0BIbaBIIsGOwVCgIB3D4QKBoBKBYp4ggU+gAWLFXyABSA50A+E"
			. "2IETMjmwMA+EZgCngThzgQ8EE76BOI1KIMcCACIAVQDHQgRuhABrAAMIbgBvAAOQDHcAbgADEF+ARUjHQhQCIUIYASFmIIlyHIkLgipmiQBKHolF"
			. "2MH4H4iJRdxIYo1F2EBiBOn8xylFtIsAi4BNtIPAAYkBwWk5BQ2JTECKQA1DDOgcAgjACk20iwGJRWaswAqCUYQXgFHCDgJkiQHBW+k2xhVBM4tx"
			. "gQcDvmzBTwEBQHHHCcAudQDBmwhmiXCS/MGcSgYEnY+LB2AikAEYdEq+QLIAiWDBjVAEvwCsQDUwIIt1pInQQVt5AsAxyYX2ficABAGOCInQv4CK"
			. "AIPBAQCDwgJmiTg5zhh17L5BBMEKMIsDBQCrAYCxGdKJC4MA4iCDwl1miRAAjWX0W15fXY0QZ/hfw0GHxwGDxAAPQUnHRCQAZMAOuUDKIwcCSYCO"
			. "AIo5AKEcjqEIoUA/QcaLEY1iQsBPD4XNwAbDxSsu/ICcATbAxZzBxXkcyA+Ov8GbRghADcNZnIMBAFyCWoUc6YzACqCNdgA5eIDRd4OtbYzR8YBi"
			. "gVf+AAwAv5hw+///ZuVmgXkhBQYlAQXIYTZFsCFnjMarwBGDNuKkM3RjZ5njDQq4IS25gyxGAo1G0gZBM04EgWR3IATACBiLVaTiZEACiMz6AUEC"
			. "pIl9nDHSjUBIAYsDic8EN4kQwYPCAQBCZscBQAkAOfp176Ehi6B9nIkDuKExZoEkhhAgFuISGA+MnCAJsjtgHYyT4SVuHQVBGDgD6bSgBONK6RRC"
			. "AhyNQuAUABGgSASFwMgPiWgAgekvgAXhdzyFeKJ7QTcpPeMIjUVAyPIPEA65QFQAFMdF4ZUAQDKhIAEBAQtNyI1NuIsQiMdFzOECx0XcwwAK5MMA"
			. "4GAEAPIPEYRN0AA3GI1N2GA3IiBCA0QkHAIJTCT6FGABEOEE4ACgfeIAQBkD4gBDSwQk/1IYiwBVwIPsJA+3ArJmoBeEE+AiITMJAAdRQCuLE7lA"
			. "NADjFYkI1onHIlsGi0XAQA+3BAiDwYEGdeDnifiJE+ArAgPhpI1CVIXGt0BUA+k6wScD4zPBZVYBiVQkBIAPtlWjiRQkYVFQ2uh9+AAnk8cEkAUB"
			. "P2ohRHAMMcDrgAmQOcIPhBKhCgLBoH/B4QQ5RA7YCHTqgX4hLWkhBearpHUSoAePoEEKfaFLAeS6gwAChdJ/cYEhjn2kixCNSsA3AAONVDoDhf9+"
			. "QgniCjnQdfdhQAgZYwnpRSJPAJSNDAAMKcriCKAEZoM8QuAAdfaLdSF2wh5hHryPaQBIpBfgWeIQlGK6ZwW84ESgLIgQ4BKBCk1ipOAKVAgB4yuj"
			. "D/khoSEB6e335yVFpACDwgOJEYXAeXjK6dXgAkAHZjjnVF2/QZ0iFeQnQ6rhI+AJH0AOoQQDhdt0d2DgdUABbL5lY6IgxwQghYKix0BA+HQAcgCB"
			. "b3JqBoKidsEo7uZf4UO43eESA0AGJQhBf3BRgCAEqgqRf/YCBAgCBDUBBFatAjsjTgQVEzfwJuma0zEWdfVIABVF3CBfYIMGEIl0iFAgDhqRMh6w"
			. "gwYiJo/6EAVs6ZbAAzAOAVEJMWW5ElshTIr2IAUD6YmDEAJhGInQD4Uz0QKqeEgIBYVJspEBTnQEm/IDASVHIQQHe4Q1wB2Z8CPpv0EGUX3pJRMC"
			. "IIsA6XD58D5VVwBWU4PsRItEJMBYi1QkXIvAj9AZGfAeji/QNGEBMf+JQNWJ+otAGIABBMlyAkAMcA3rJfMpAAF0OVAgWsvBFaADYUwEVCQQcS/t"
			. "IAE5EDN+ANqLBCQxycZEBCQPQEJMJEKLSCAIhcl5BwEBAfci2UA1ELsUgR3NzATMzPVQyInfg+sAAffmweoDjQQAkgHAKcGNQTAAidFmiURcGoVg"
			. "0nXfgHzQBCALEJB0ErgtsStf/rIBgcMAXFwaZjlF4GQOaQSSAG7QP0tmO0RaTVABU1ABUUDpEAtgAIs8JIk4g8RENrhxR+FOw3AwEAsPtwJdYDwI"
			. "D7cOZjkQyw+FHzADMcBmoIXJdStm0CjFyw7MhRPgAUAEMcATBPWQMaACD4TkYBpQLQ+3AAxGD7dcRQBmwDnZdLbpzlAB8hcgMduB7JzhE4QkIrAC"
			. "WpwkjuEArCQitGEAUASL4EOJ0wSBwdAAgIPTAIMg+wAPhwvBTse+hXETuXEThcB4a3ALAIn4g+4B9+GJAvhxExySidcB2yAp2IPAMLARdGYJcRON"
			. "VHAA7Q+EkpmhBU0AsFFyHInLkAAEicbRUYkDD7dCIv7hEeqJTdAIM4FWxNEJmw25Ahswdla4EGdmZmZABOkB9wLvwAf4H8H6AikCwpAbjQRGKfiJ"
			. "CtfwB0zxB9eD6wKDIhrBGmaNVFxm0gDJEAmFbhGxhCRROrAIEyBBckvCAqJLev4AkHXzi7TSAYkGGwkB8gtEJEiNRCRAW3IJwABUImlwOEDSJFQQ"
			. "JEyLELEnQI1MRCQw8mdMJFTgAUTVxGVYdABgdABcRGgPagsPag9qGNBpi1wkOCgPtwMSarqgHoXtYHQ/i1UAs2n2Vol200AX8WkD8CTwAgZq5jyJ"
			. "VQAO1heSDtQRixBuuEIEcQ8wJQOUg5Ap8aEUAokQ6UfRJZD0PQoEgDIcAAYYi2wkkiBAZoSNQUkKvnHMAI1ZAokaZokxCA+3CCAEdHQPtkIdAQ2I"
			. "XCQB8AlmQIP5Ig+PPuF9gyD5Bw+OdJAAjVkA+GaD+xoPh6gBUAQPt9v/JJ2cF7AQ8gjBBUCRQwq/XAHCBQRmiTmJGrsBkQZmiVkCD7dIKwAdwgqk"
			. "sQIsgQgajSBDAokCuDMCA4MsxAR3HTEC8DEPCr4p8QS/ckUFMUELeQK86670XXAC0tN8B2Z0B1TrhncCoHICu3ECvhpu8gEZ8ALxBHEC6cpbAUN2"
			. "cAJ0fL0E4cVZsQTpN3fTcAJUtQliGbwJ6Q93AtATXA+FdneQERADItUHQQDaB93pdX+DRVBbz9EA8wPgTuoB8FylJAwFIhZDBDFxA0kEgByJy4nO"
			. "g+MAD2bB7ggPtpsCiMAZg+YPD7a2A5EAgB0CictmwekADGbB6wQPt8lxgAIPtrmhAbQCEAIDI0EGwUiJ+4uQcb77/InzUAAxALAB0BBxBqAQcASN"
			. "WQhAB1EB4QAGROkd9QuNWYEwIiEID4ZOoVaD+R8PLIZEkADAD23gHnMCgIkyZokL6e731AJ9kCQIjV8BiV3OAMAhkPKgAYPD4QD6IKaL8ABSAevo"
			. "dxIKdxYx8AAE6ZcH0fAAAekWh/AABBRkoQJZ4GYSsACD+14Ph7L+/4D/6Wn///+QBgA="
			static Code := false
			if ((A_PtrSize * 8) != 32) {
				Throw Exception("_LoadLib32Bit does not support " (A_PtrSize * 8) " bit AHK, please run using 32 bit AHK", -1)
			}
			; MCL standalone loader https://github.com/G33kDude/MCLib.ahk
			; Copyright (c) 2021 G33kDude, CloakerSmoker (CC-BY-4.0)
			; https://creativecommons.org/licenses/by/4.0/
			if (!Code) {
				CompressedSize := VarSetCapacity(DecompressionBuffer, 5678, 0)
				if !DllCall("Crypt32\CryptStringToBinary", "Str", CodeBase64, "UInt", 0, "UInt", 1, "Ptr", &DecompressionBuffer, "UInt*", CompressedSize, "Ptr", 0, "Ptr", 0, "UInt")
					throw Exception("Failed to convert MCLib b64 to binary", -1)
				if !(pCode := DllCall("GlobalAlloc", "UInt", 0, "Ptr", 8216, "Ptr"))
					throw Exception("Failed to reserve MCLib memory", -1)
				DecompressedSize := 0
				if (DllCall("ntdll\RtlDecompressBuffer", "UShort", 0x102, "Ptr", pCode, "UInt", 8216, "Ptr", &DecompressionBuffer, "UInt", CompressedSize, "UInt*", DecompressedSize, "UInt"))
					throw Exception("Error calling RtlDecompressBuffer", -1, Format("0x{:08x}", r))
				for k, Offset in [24, 509, 598, 1479, 1671, 1803, 1828, 1892, 2290, 2321, 2342, 3228, 3232, 3236, 3240, 3244, 3248, 3252, 3256, 3260, 3264, 3268, 3272, 3276, 3280, 3284, 3288, 3292, 3296, 3300, 3304, 3308, 3312, 3316, 3320, 3324, 3328, 3332, 3336, 3340, 3344, 3348, 3352, 3356, 3360, 3364, 3368, 3372, 3376, 3380, 3384, 3388, 3392, 3396, 3400, 3404, 3408, 3412, 3416, 3420, 3424, 3428, 3432, 3436, 3847, 4091, 4099, 4116, 4508, 4520, 4532, 5455, 6153, 7138, 7453, 7503, 7916, 7926, 7953, 7960] {
					Old := NumGet(pCode + 0, Offset, "Ptr")
					NumPut(Old + pCode, pCode + 0, Offset, "Ptr")
				}
				OldProtect := 0
				if !DllCall("VirtualProtect", "Ptr", pCode, "Ptr", 8216, "UInt", 0x40, "UInt*", OldProtect, "UInt")
					Throw Exception("Failed to mark MCLib memory as executable", -1)
				Exports := {}
				for ExportName, ExportOffset in {"bBoolsAsInts": 0, "bEmptyObjectsAsArrays": 4, "bEscapeUnicode": 8, "bNullsAsStrings": 12, "dumps": 16, "fnCastString": 288, "fnGetObj": 292, "loads": 296, "objFalse": 3192, "objNull": 3196, "objTrue": 3200} {
					Exports[ExportName] := pCode + ExportOffset
				}
				Code := Exports
			}
			return Code
		}
		_LoadLib64Bit() {
			static CodeBase64 := ""
			. "NLocAQAbAA34DTxTSIMA7EBIiwXkDAAAAEiLAEiJ00ggOQEPhIUANEiFENIPhJwBEIsCQQS5XwEQiUwkOEgAuiIAVQBuAGsIAEiNARyJEEi6IG4A"
			. "bwB3ABNIiQBQCEi6XwBPAIhiAGoBDRC6dAA3AGaJUBxIjVAgQMdAGGUAYwAXEwBIidpmRIlIHsjo/BkBXwNBAFQACBiNUAIAHAAZEDHAAEiDxEBb"
			. "w4tEACRwRQ+2yYlEgCQg6K8OAAAFGAgPH4ABv0GDABAsMdIDTAFHTAAUYOiKpoAqTAAdYDHAABAaAYMYkAEAHJcAQVUAQVRVV1ZTSIEk7MgBB7sU"
			. "gV9EiQIagYyJzUjHQggBARNIiwEPtxBmQIP6IA+HzYAHSQC4/9n///7//wD/SQ+j0A+CMQICgWZIApAPtxFoSInIAxSgARQAD0gAjUkCc+ZIiUUC"
			. "AIALWw+EzQUAMAAPjhMAGYAHbg8MhDyAB4AEdA+FtgIDA4pmg3gCckjAiVUAD4XXgOAACVIEAAkEdQMJxIMEBimABAZlgwSxgQSDwIAIgD3a/f//"
			. "QFxARQAPhCkHADS6wYAUAEjHQwhBggA2YBMxwOmIwALEU0iEiU3BHnsPhWAAMwGAEAJIjVQkcGYAD+/ARTHJSIsMDcsAOYETRTHASQK8BT0PKUQk"
			. "UEjIjbwkwVdIxwBeBEmgSIlUJDBBEFBBArYoQGoAB0ACBwACOAECBcABIMEi/1AwSIsAdCR4SItFAOlijQAEDx9EwSNCSToYD4XeAQ3BI4naSCSJ"
			. "6cEF6E/AHoXAiA+FwwIblCSYAVgAidhIifHodAsngQRAPUNpdyUAXtQPzIKjQD/CFQ+3gJpAExlCZoZ+wVlDGiwPhXFBAw8fhMKDQxzGEQ8MhosA"
			. "B0ACfQ+EV4FDAiJ1R0iJ+oAkhOjAgFqFwHU4yB2ID4c/w4TUciHPHaSHHgQHc+jBGLhAAxD/SIHEAZ5bXl9AXUFcQV3DAAotIHQPD44zgIeD6oIw"
			. "gAMJd9ZBvIGlB0FxwSigOCNIi1UACEgPv+AK+C0PhAJE4ALyDxAVTgoFID64Ij2D+DAPhAIP4AKNSM9mg/kACHeRSItLCJAYSIPC4BtgB40UiYEA"
			. "aFDQSIlLCIUJAESNSNBmQYP5CAl22OAHLg+EUREgSIPg34ABRQ+FBurCI8MHZoM7FA8UhCQBWbdkEP0EAAWARMmAASt1D0iNoEoCD7dCYAVNAC1G"
			. "yuEKwAoPhwmCTMIgAkUx22biI4PoADBDjQybSYnSQcECmESNHEjgBv4RBAZ24EyADUWF24gPhBNAGUGD+2CVAv+AEvMPfgVxCQAAAESJ2jHA0QDq"
			. "Zg9vyIPAAQBmD3LxAmYP/gLBAAHwATnQdecAZg9+wmYPcNgC5QAB2A+vwkGDAOMBdAWNBIABIsBBXPIPKmAAEEuACEWEyQ+EIgALAPIPXsjyDxFL"
			. "MAgPtwNAGYAcMwYBoikFD4XC/P//QPIPWVMIMYAGEXBTCOlA4FHkaOA0ZlgPhSqBZeR3YSNzF2tDAuJ3bEMCBEMC4ndzrUMC8UBJQAIIQAIIRHoC"
			. "3kECg8AKgD0HyvpGenhgUEG4RXoBD0QxwMBBA+m1oAUPRB9AAlQPhaKgAUypwJFBuGEETIAwTMA8FQEFTGBVQYNVIg+EBjkAOGAMBEyNFYMRgB/r"
			. "HZBAt/5JiXDBSYnIoQQkVyAFL2uhIAHER0ALSUALBIdcXHXNAAUhHqEE2iMhL4gPhOQgC4PqXIABEBkPhxOBE7fSSQBjFJJMAdL/4oQPH+Gi1A+D"
			. "ZiAqweNwOH0PheyhASAOHEG5IDsCHoIbC0iJsHMI6dSAA+YGVoAB4aARdMfpuGEGJC7Eo3alQwIpLpJDAiIuRAJ/M4MNIKbY+MYrgq2LBarngBe6"
			. "ISdmIddD4D3U6VXABblh1knAJQAkIGaJSP5MYAbp1dOBOc+mlPnGpr/hcYakwEG9zczMzEepn6Z3iaYCr5JTRYAK0FN2SgzDMl3RF10PhLaQBdIa"
			. "ZreCFAFU6BIQCcFThgD7//9FMdKJ+US6E7NElCS4QSKNDpTSXPQs8B+JyEkPAK/FSMHoI0SNAAyARQHJRSnIAEGDwDBmRYkEAlLQAYnBSInQSACD"
			. "6gFBg/gJdwjOSJijWEmNFEKs6OWBJehYTONYCrAHmWFyZi71VvdydyQxAoWycuq0WV0PhdiwL4zp58It+WosdeBBF3iDxwF0AcEqQwNgVvdL4A8D"
			. "B+3UGevfMBnwRXAzuKElZokDY08BtP9QwR14QAbwAeDBNXeyJ1MnGAJWEAKTAYABi2wNlvJj+AE2EQQ0T0FmuQIfk0/pASAPYSG+ARARAPJIDypD"
			. "CChmiTPwQ0NiV+m8nZADSdAqMCWBKTHSETghIDVIBI1RMFD6CSB2HY1Rv4AABQ9EhuswYY1Rn8IAhyK+8ByNUamwOAbBDOIEchGUAwZEjVnBcVz7"
			. "CQ+GlSAD4ABWv+EAEASO4wCf4wCHUnoxBFQKQQQITAQIVUgESEsEW0sENUcECrVMBApIBPtQEUgEDUsExvBAOEIEg8AM0QOyNS55sBNSF003YIAB"
			. "QbuiDZgBRIlYowFFoQFWvME7pwFgowEqoAG61lzpBHQGEYABvqBzhwFqcIMB+MAZv5CyhwF4RYMB34ABTInIYDRQAPxFMe1JjUACJWAxKTNL6SjA"
			. "DEwPYK9DCEG7oVpSTBtyTIBE6Q6QAYFuESG/8xEhwnSJO4MhViFAdSZzxv5QAhIljQyJ0HKRA2micgHJoADJ8QNTbCrCybBrwfIPWHsEN314v+kx"
			. "0Qd0YxJEgFMP5LdAEn3pCsEBICyAgBRCAsGECRAaScfAc0KKxCym9xJwUAYABumi2RADQb0vqhZo8xECv+FPi0MIRInKECnC6ddQOEQB2rTpH3QA"
			. "0vA8cQCFcABRQB/J6XyFAP2FAK9hgQBRyekdcAAViIQyfuAH6XpQByKO6TXzkACACgVY0ADCAP++DwADDwAKADAxMjM0NQA2Nzg5QUJDRARFRjEB"
			. "BBAAANwQDwAArDAAlREA9AB8cABUtAA/AD8APwArPwAxAPzgzmDwDuz1tT8ARXwBkn8COgB5/AEqKvQAEXAA9SFJAGFgAGwAcwC13RXdX0QAVpIB"
			. "dQBlWBHw3j90ALJsOeWS04hxbVNPKdFsy0gwZajy3VQkEFRMicZibUyNhGlCATHSwGxURW1xAP8MUCgg4cECYEiJdHdBAOACYHSL0APwc0FwcNWz"
			. "X9mxAGi0A3B1datynYEAMOUFMKmBxg+3oH8Q+Al0SVAAA3QLAzC3IQtbXsOQSIuEdgjhb4BIAfCgbhggdOOBxXEKTI1EJCRYIAfomRBIhcAYdMpI"
			. "AOYAATDrwJFwdkiLTtNfEJDYBECQkEFXQVY45fgRMnu0JMByALwk0IFwAEQPKYQk4IEAMIukJGARh6Dmi1EEIERA7VxJic1NmInHRJDn4HuFLkFS"
			. "YA+2NRbw4DRRsDilugACAABBgP4BGQDJg+Egg8FbSACLA0mJwEiDwAACgHwkXABIiQADZkGJCA+FjQAFAABIhdIPjgCjAQAAZkQPbwAFE/7//2YP"
			. "bgQ1IwAOMfbzD34EPREAEkiJ90jBAOcFSQN9GEiFEPYPhSUAvkCE7QAPhaQDAABFhAD2dX9JOXUwDwiOvQQBntsPhCwCBwAIixNIjUICMEG7IgAA"
			. "DAByRIkAGkiLRxBNifgASInaSI2MJKBFAhiEAgfoCQoCMkEWuAEuACsCATxIjVAIArk6AiYTZokIKQBzdBQAEwQADrogAQEniVACDx9AAACLRxiD"
			. "+AEPhAIEAJiD+AYPhFshAgQFD4RyAEmD+FACD4TRhU14AQSLsANBul8AIAJG+QApAB5EDxEAZg/WgHgQZg9+cBgAMIMAUgBDUBzobwkDGA65AmSA"
			. "SAFGRIkISAiDxgGAeyAPj9xjgJGCrA+E6oCIAjPQQQEWiwtBuw0ABL4TAG4AHVEEgBsZSIkC0AJncQIxyUWFIOR+KWaQAAlBuAEAMwCDwQFIg8IC"
			. "AgATAEE5zHXnHrkBCgN+AUGA6UiNSAACGdJIiQuD4gAgg8JdZokQDxAotCTAABMPKLwCJIE6RA8ohCTgEcENgcT4gAFbXl8AXUFcQV1BXkFAX8Nm"
			. "Dx9EQAY7IFEwD4TmQEJFMRj2uXvBCsAshdT9QP//QYMHAcQyFkuAh4ADAoGIj93BBosAF41KAo1CA0JQjVQiA8EuD8MTiQDBg8ABOcJ19whBiQ8B"
			. "EOlo//9o/w8fQ0L3AJdBQrheLANBwU8APMA4AQKRR2PAagCRD4U2gFECko8GwwAbQAI4f1pIi8xPEEBiwGnoJ8NhRGBOuoGFQD+EfoUFQq4floRA"
			. "BYR12kB26LJAotzpUsAGwz3BI5bCI8BzEnTDcxBIQHZPAGIIAGoAA4VIiQjHIEAIZQBjwaFIDGGDe1AO6T5AJcRPi0APSDsN1vmAFYSiwMGTOw2p"
			. "AgPjApcEBawAA0g5wQ+EojPCAwBIOQCnV4WGAvABBb8iAFUAbiwAa4Eigis4gCIgSEC/bgBvAHcABkjAiXgISL9fBCZAA0QQv8Erx0AYAiaJ3Hgc"
			. "AUGBKwDBHkI7RNSJRNbpQ8AVDx+A4SFhQDUPiFP8gBLhD9YBARGLA0WNRCQBhDHS4WdIicFBQk2Ug8LgT8DhTwlE4DmE57rjTwNmiRFCNJKTYAhJ"
			. "O0A0jB0hAXFANA+PsyGEwDSDLuhKgCEu1eFRHwABRkJQAUGJBwI99gU9TZtjBwA9BkARogiOWCABs0BHwFxHEEUYIAoxQF1lJITnwVGLByBNoQmE"
			. "jjgABkAVgAvp/fvkOwRBuqFtSI1BBkGeu0Fu4BjBTWGPWQSBIGyJBABTYhDJYAYjGVM3ogfiJAMa1gAnCBqvBuXkNq3jJulmAAbkQMEC4gvCBQPp"
			. "XqAa5AjgQyWEB3KAB+nS5hODByMBA4Ea+egXw2sB6RKz5glBueEXSY1AiAZBuuIXRYlI4hcMRYmAnsFwVvr//wTppOUJ8g8QB0gAjVQkYGYP78kA"
			. "RTHJSIsNMesRoBGNhCThEEUxwAxBu6AMpqxIiwFIgIlUJDBIjZTiAQgPKYwCBUjHhCTGsCJnYQVUJCggFEAC1pBEAsAnnOYEqIQCRAZjgGnAAkQk"
			. "QGIHAAE4EYIDRCQgIQPyDxEIhCSIAAH/UDBIAItUJGgPtwJmYIXAD4S/4BiiJ7+5whITuWBD4K/kd0ngoaSJwSKhQYnAA0QBB0oEIK7BoQd14EFy"
			. "RbCJCOl5oAjhV0FBWVBED7bNoy6JoA/otJj4ICVYAgSD3MIAEiBMi0EYuAET6xQB4l6NSAFIOcIPJISEYYKJyOBgSMEA4QVJOUQI8HQ24mCjQhTp"
			. "gAiCpOmzV2AK4gZBMcsBDA5AMUEfoIGA1eEMAFJAuGaDeJD+AHXygKHp1yCBAGaQg8IDQYkXaQBQeV2CT0ygAoJPjfqKYYqQw1pCWYBI4MHBDpNh"
			. "uuBKuWzgAEG4oQCpIIQIx2CDdWB+SIHgYQAzQAbpc2EM40eLEgdAsyABobHQdfkNAQVdUArELDHS6OObUTbGBsXiDHMsdFRCcRJ1wQa7ZcYGdABy"
			. "h+EfIndwAFgG6QWxTYXwAm2xWIsV2fUAEEq5AgOJgDtQCoMCSBgI6dzQBfAtBOnTZ4MAIwhtSugQwYphMKydYQK+8iThD1ENuVtRF8Q99/IDBemK"
			. "FgKCAdUyayDCAQA1a35QA+AACALpUIEAiwfp0AEAGpBBV0FWQVUAQVRVV1ZTSIMA7EhIi2kgSYkAzEmJ0kiF7Q8MjlDRHyAkEEyLcQFgKnkYRTHb"
			. "SL4UzcwDAEjgJAjrJKFxH005XCSwSuUhKgSDw6BSxyBMOd0YD4QPAATzAd5+24HRFjHSRTH/ZpA0ADhIhcl5CUj3CNlBv5INjVwkNhhBuRTiUXFX"
			. "yEWJAM1Ig+sCQYPpgAFI9+ZIweoAbgAEkkgBwEgpwQCNQTBIidFmiQJDIXh10k1jyUUAhP90F0WNTf4EuC3xUWPJZkKJCERMENIASItcJAAISo0M"
			. "S2ZBOdACD4VbkE64UTVwKQgPtxRzXUE7VAJQ/g+FP7ABZiAF5whJiTjiMEiDxEgDf4LgMk8QQQ+3CgEwABFmOcoPhQYHRQXzATEEI2aFyXQSt+kQ"
			. "hfXRo8DrquP2PCACD4TKUAGABJMIEYAATAL+MAV0u+lasYABkAoAUho4AE1BHLoT0Qm2GJAlTCQoAEyLCUmJ00iJQONNhcl4e/ANTCCJyEyJyfgT"
			. "SYkC0SMUTInQg8EwgVASDFNJg+oBchSkSJggAkNNQSamkRx/gKoQCfEYcEfCCbAEs0cIEA+3SP7QC3XlMQzASUNHoBI4W17DI/IPghxBujAyCmdm"
			. "IwMA8whI9+5RAMH4AD9IwfoCSCnCAWEJQY0EQkQpyMHQCWaJREv+EUdxH0FACc2D6AK6URy5QaIcmGaJFERVCoXiWlAXQYsQEhzzOnFG/sJ1RlBe"
			. "oDdjCfMTYC4REAlQSoSh0BpIiwJBIrrVq0mJEVAUEA8UtwGCWIISo7Yd6QDj//9MjRU28WHxR2aD+CKwZlHBgyD4Bw+OjJAAjVAA+GaD+hoPh6gB"
			. "EAUPt9JJYxSS4EwB0v/i8A5wGPCNwUACSYsBvlwQBdCNIdIGBGaJMAEHiXih8hUPt0ECRVybQgMiIsAESYsR8VNJifIBw7+JAqAoABbwNCECkv8y"
			. "GgG6cQW7clOfU6EFcgVYAmAmkHIC18V5AmZ/AoJmLvah8QKWp/MC8wpu/grpTzKsc/J88AJ0e7YCdKO5AiOr865xAlN2AmJ/AvuSqGFRFVwPhV8A"
			. "ExEDIWdWC0EAWwvpycExEk2/q7ID85yEsCuPhQzuiQ8HAVwrBJAeSI0VSe8RcdzDg+Mgu740GkCJw2bB6wTTADxZ0gDoDBAB8C7AQwEc0hpAABQC"
			. "AgadAwZjBQ4IMQXADOMFcAbpJxF3CY1QgTAiIQ+GgmQBRoP4Hw+GsStVQQ5sUh5aUB4ZAB7ppvJxb/YYQYugAwGACvOALFEphWrgAQAu4AChIGXw"
			. "cRDTAOvwdJTwECRj9xnwAATpn/euAWHpFo/wAIISZoACjVDgkZAJXg+HUUjpaxABAflG"
			static Code := false
			if ((A_PtrSize * 8) != 64) {
				Throw Exception("_LoadLib64Bit does not support " (A_PtrSize * 8) " bit AHK, please run using 64 bit AHK", -1)
			}
			; MCL standalone loader https://github.com/G33kDude/MCLib.ahk
			; Copyright (c) 2021 G33kDude, CloakerSmoker (CC-BY-4.0)
			; https://creativecommons.org/licenses/by/4.0/
			if (!Code) {
				CompressedSize := VarSetCapacity(DecompressionBuffer, 5343, 0)
				if !DllCall("Crypt32\CryptStringToBinary", "Str", CodeBase64, "UInt", 0, "UInt", 1, "Ptr", &DecompressionBuffer, "UInt*", CompressedSize, "Ptr", 0, "Ptr", 0, "UInt")
					throw Exception("Failed to convert MCLib b64 to binary", -1)
				if !(pCode := DllCall("GlobalAlloc", "UInt", 0, "Ptr", 7984, "Ptr"))
					throw Exception("Failed to reserve MCLib memory", -1)
				DecompressedSize := 0
				if (DllCall("ntdll\RtlDecompressBuffer", "UShort", 0x102, "Ptr", pCode, "UInt", 7984, "Ptr", &DecompressionBuffer, "UInt", CompressedSize, "UInt*", DecompressedSize, "UInt"))
					throw Exception("Error calling RtlDecompressBuffer", -1, Format("0x{:08x}", r))
				OldProtect := 0
				if !DllCall("VirtualProtect", "Ptr", pCode, "Ptr", 7984, "UInt", 0x40, "UInt*", OldProtect, "UInt")
					Throw Exception("Failed to mark MCLib memory as executable", -1)
				Exports := {}
				for ExportName, ExportOffset in {"bBoolsAsInts": 0, "bEmptyObjectsAsArrays": 16, "bEscapeUnicode": 32, "bNullsAsStrings": 48, "dumps": 64, "fnCastString": 304, "fnGetObj": 320, "loads": 336, "objFalse": 3360, "objNull": 3376, "objTrue": 3392} {
					Exports[ExportName] := pCode + ExportOffset
				}
				Code := Exports
			}
			return Code
		}
		_LoadLib() {
			return A_PtrSize = 4 ? this._LoadLib32Bit() : this._LoadLib64Bit()
		}
		
		Dump(obj, pretty := 0)
		{
			this._init()
			if (!IsObject(obj))
				throw Exception("Input must be object", -1)
			size := 0
			DllCall(this.lib.dumps, "Ptr", &obj, "Ptr", 0, "Int*", size
			, "Int", !!pretty, "Int", 0, "CDecl Ptr")
			VarSetCapacity(buf, size*2+2, 0)
			DllCall(this.lib.dumps, "Ptr", &obj, "Ptr*", &buf, "Int*", size
			, "Int", !!pretty, "Int", 0, "CDecl Ptr")
			return StrGet(&buf, size, "UTF-16")
		}
		
		Load(ByRef json)
		{
			this._init()
			
			_json := " " json ; Prefix with a space to provide room for BSTR prefixes
			VarSetCapacity(pJson, A_PtrSize)
			NumPut(&_json, &pJson, 0, "Ptr")
			
			VarSetCapacity(pResult, 24)
			
			if (r := DllCall(this.lib.loads, "Ptr", &pJson, "Ptr", &pResult , "CDecl Int")) || ErrorLevel
			{
				throw Exception("Failed to parse JSON (" r "," ErrorLevel ")", -1
				, Format("Unexpected character at position {}: '{}'"
				, (NumGet(pJson)-&_json)//2, Chr(NumGet(NumGet(pJson), "short"))))
			}
			
			result := ComObject(0x400C, &pResult)[]
			if (IsObject(result))
				ObjRelease(&result)
			return result
		}
		
		True[]
		{
			get
			{
				static _ := {"value": true, "name": "true"}
				return _
			}
		}
		
		False[]
		{
			get
			{
				static _ := {"value": false, "name": "false"}
				return _
			}
		}
		
		Null[]
		{
			get
			{
				static _ := {"value": "", "name": "null"}
				return _
			}
		}
	}
	
}