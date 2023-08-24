﻿class Chrome
{
	static version := "1.3.4-git"
	
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
			if (A_TickCount-StartTime > Timeout*1000)
				throw Exception("Get page list timeout", -1)
			else
				try
				{
					http.Open("GET", "http://127.0.0.1:" this.DebugPort "/json", true)
					http.Send()
					http.WaitForResponse(-1)
					if (http.Status = 200)
						break
				}
			
			Sleep, 50
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
		Timeout    - Maximum number of seconds to wait for the page connection
		fnCallback - A function to be called whenever message is received from the page
	*/
	GetPageBy(Key, Value, MatchMode:="exact", Index:=1, Timeout:=30, fnCallback:="", fnClose:="")
	{
		Count := 0
		for n, PageData in this.GetPageList()
		{
			if (((MatchMode = "exact" && PageData[Key] = Value) ; Case insensitive
				|| (MatchMode = "contains" && InStr(PageData[Key], Value))
				|| (MatchMode = "startswith" && InStr(PageData[Key], Value) == 1)
				|| (MatchMode = "regex" && PageData[Key] ~= Value))
				&& ++Count == Index)
				return new this.Page(PageData.webSocketDebuggerUrl, Timeout, fnCallback, fnClose)
		}
	}
	
	/*
		Shorthand for GetPageBy("url", Value, "startswith")
	*/
	GetPageByURL(Value, MatchMode:="startswith", Index:=1, Timeout:=30, fnCallback:="", fnClose:="")
	{
		return this.GetPageBy("url", Value, MatchMode, Index, Timeout, fnCallback, fnClose)
	}
	
	/*
		Shorthand for GetPageBy("title", Value, "startswith")
	*/
	GetPageByTitle(Value, MatchMode:="startswith", Index:=1, Timeout:=30, fnCallback:="", fnClose:="")
	{
		return this.GetPageBy("title", Value, MatchMode, Index, Timeout, fnCallback, fnClose)
	}
	
	/*
		Shorthand for GetPageBy("type", Type, "exact")
		
		The default type to search for is "page", which is the visible area of
		a normal Chrome tab.
	*/
	GetPage(Index:=1, Type:="page", Timeout:=30, fnCallback:="", fnClose:="")
	{
		return this.GetPageBy("type", Type, "exact", Index, Timeout, fnCallback, fnClose)
	}
	
	/*
		Connects to the debug interface of a page given its WebSocket URL.
	*/
	class Page
	{
		Connected := False
		ID := 0
		Responses := []
		
		/*
			wsurl      - The desired page's WebSocket URL
			timeout    - Maximum number of seconds to wait for the page connection
			fnCallback - A function to be called whenever message is received
			fnClose    - A function to be called whenever the page connection is lost
		*/
		__New(wsurl, timeout:=30, fnCallback:="", fnClose:="")
		{
			this.fnCallback := fnCallback
			this.fnClose := fnClose
			; Here is no waiting for a response so no need to add a timeout
			this.BoundKeepAlive := this.Call.Bind(this, "Browser.getVersion",, False)
			
			; TODO: Throw exception on invalid objects
			if IsObject(wsurl)
				wsurl := wsurl.webSocketDebuggerUrl
			
			RegExMatch(wsurl, "page/(.+)", targetId)
			this.targetId := targetId1
			ws := {"base": this.WebSocket, "_Event": this.Event, "Parent": this}
			this.ws := new ws(wsurl)
			
			; The timeout here is perhaps duplicated with the previous line
			StartTime := A_TickCount
			while !this.Connected
			{
				if (A_TickCount-StartTime > timeout*1000)
					throw Exception("Page connection timeout", -1)
				else
					Sleep, 50
			}
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
					, "pageRanges: "1-5, 8, 11-13"}) ; String value
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
			
			; Use a temporary variable for ID in case more calls are made
			; before we receive a response.
			ID := this.ID += 1
			this.ws.Send(Chrome.JSON.Dump({"id": ID
			, "params": Params ? Params : {}
			, "method": DomainAndMethod}))
			
			if !WaitForResponse
				return
			
			; Wait for the response
			this.responses[ID] := False
			StartTime := A_TickCount
			while !this.responses[ID]
			{
				if (A_TickCount-StartTime > Timeout*1000)
					throw Exception(DomainAndMethod " response timeout", -1)
				else
					Sleep, 10
			}
			
			; Get the response, check if it's an error
			response := this.responses.Delete(ID)
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
			response := this.Call("Runtime.evaluate",
			( LTrim Join
			{
				"expression": JS,
				"objectGroup": "console",
				"includeCommandLineAPI": Chrome.JSON.True,
				"silent": Chrome.JSON.False,
				"returnByValue": Chrome.JSON.False,
				"userGesture": Chrome.JSON.True,
				"awaitPromise": Chrome.JSON.False
			}
			), , Timeout)
			
			if (response.exceptionDetails)
				throw Exception(response.result.description, -1
					, Chrome.JSON.Dump({"Code": JS
					, "exceptionDetails": response.exceptionDetails}))
			
			return response.result
		}
		
		/*
			Waits for the page's readyState to match the DesiredState.
			
			DesiredState - The state to wait for the page's ReadyState to match
			Interval     - How often it should check whether the state matches
			Timeout      - Maximum number of seconds to wait for the page's ReadyState to match
		*/
		WaitForLoad(DesiredState:="complete", Interval:=100, Timeout:=30)
		{
			StartTime := A_TickCount
			while this.Evaluate("document.readyState").value != DesiredState
			{
				if (A_TickCount-StartTime > Timeout*1000)
					throw Exception("Wait for page " DesiredState " timeout", -1)
				else
					Sleep, Interval
			}
		}
		
		/*
			Internal function triggered when the script receives a message on
			the WebSocket connected to the page.
		*/
		Event(EventName, Event)
		{
			; If it was called from the WebSocket adjust the class context
			if this.Parent
				this := this.Parent
			
			if (EventName == "Error")
			{
				throw Exception("Error: " Event.code)
			}
			else if (EventName == "Open")
			{
				this.Connected := True
				BoundKeepAlive := this.BoundKeepAlive
				SetTimer, %BoundKeepAlive%, 15000
			}
			else if (EventName == "Message")
			{
				data := Chrome.JSON.Load(Event.data)
				
				; Run the callback routine
				fnCallback := this.fnCallback
				if (newData := %fnCallback%(data))
					data := newData
				
				if this.responses.HasKey(data.ID)
					this.responses[data.ID] := data
			}
			else if (EventName == "Close")
			{
				this.Disconnect()
				fnClose := this.fnClose
				%fnClose%(this)
			}
		}
		
		/*
			Disconnect from the page's debug interface, allowing the instance
			to be garbage collected.
			
			This method should always be called when you are finished with a
			page or else your script will leak memory.
		*/
		Disconnect()
		{
			if !this.Connected
				return
			
			this.Connected := False
			this.ws.Delete("Parent")
			this.ws.Disconnect()
			
			BoundKeepAlive := this.BoundKeepAlive
			SetTimer, %BoundKeepAlive%, Delete
			this.Delete("BoundKeepAlive")
		}
		
		#Include %A_LineFile%\..\lib\WebSocket.ahk\WebSocket.ahk
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
	
	#Include %A_LineFile%\..\lib\cJson.ahk\Dist\JSON.ahk
}
