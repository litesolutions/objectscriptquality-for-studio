Class %ZStudio.SourceControl Extends %Studio.SourceControl.File
{

/// Return the name of this item without the prefix to be added by ExtName
ClassMethod Name(InternalName As %String) As %String [ Private ]
{
  If $Data(^Sources)'=11 Quit ""

  If $$CheckProtect^%qccServer(InternalName) Quit ""

  Set nam=$Piece(InternalName,".",1,$Length(InternalName,".")-1),ext=$Piece(InternalName,".",$Length(InternalName,".")),ext=$ZConvert(ext,"l")
  If nam="" Quit ""
  If ext="prj",nam["Default_" Quit ""
  If ext="cls",$$$defClassKeyGet(nam,$$$cCLASSgeneratedby)'="" Quit ""

  If ext="cls"||(ext="prj")||(##class(%RoutineMgr).UserType(InternalName)) {
    Quit $Translate($Translate(nam,".%","/")_"."_ext_".xml","\","/")
  }
  Quit $Translate($Translate(nam,"%.","_/")_"."_ext_".xml","\","/")
}

Method OnAfterCompile(InternalName As %String) As %Status
{
  Set tSC = ##super(InternalName)
  If $$$ISOK(tSC) {
    Set tSC = ..SonarLint(InternalName)
  }
  Quit tSC
}

Method SonarLint(InternalName As %String) As %Status
{
  Set ext=$ZConvert($Piece(InternalName, ".", *),"l")
  If ext'="cls" Quit $$$OK

  Set className = $Piece(InternalName, ".", 1, *-1)
  If ($$$defClassKeyGet(className,$$$cCLASSgeneratedby)'="")
    ||($$$defClassKeyGet(className,$$$cCLASShidden)) {
    Quit $$$OK
  }

  Set resName="sonarLint"_$Job
  If '$System.Event.Defined(resName) {
    Do $System.Event.Create(resName)
  }

  Set forStudio='$IsObject($Get(%request))

  Job ..SonarLintJob(InternalName, resName, forStudio)
  Set child=$ZChild

  Write !!,"-------------  SonarLint  -------------",!
  For {
    Set $ListBuild(sc,data)=$System.Event.WaitMsg(resName, 2)
    If sc<=0 {
      Quit:'$Data(^$Job(child))
      Continue
    }

    Write !,data
  }
  Write !!,"-------------------------------------------",!
  Do $System.Event.Delete(resName)

  Quit $$$OK
}

ClassMethod SonarLintJob(InternalName As %String, ResourceName As %String = "", forStudio As %Boolean = 0)
{
#define addLine(%text) if ResourceName'="" { do $system.Event.Signal(ResourceName, %text) } else { write !,%text}

  Set ext=$ZConvert($Piece(InternalName, ".", *),"l")
  If ext'="cls" Quit $$$OK
  Set className = $Piece(InternalName, ".", 1, *-1)
  If ($$$defClassKeyGet(className,$$$cCLASSgeneratedby)'="")
    ||($$$defClassKeyGet(className,$$$cCLASShidden)) {
    Quit $$$OK
  }
  Set classFileName = className _ ".cls"

  Set binPath=$System.Util.BinaryDirectory()_"/sonarlint/bin/"
  Set sonarlint=##class(%File).NormalizeFilename("sonarlint", binPath)

  Set tempDir=$$$FileTempDir
  If '##class(%File).CreateDirectoryChain(tempDir) {
      Quit $$$ERROR(5001, "")
  }
  Set tempDir=##class(%File).NormalizeDirectory(tempDir)
  Set fileName=##class(%File).NormalizeFilename(classFileName, tempDir)

  Set tSC=##class(%Compiler.UDL.TextServices).GetTextAsFile(, className, fileName)
  If $$$ISERR(tSC) Quit tSC

  Try {
    If $ZVersion(1)=2 {
      Set cmd="cd /D "_tempDir_" && "
    } Else {
      Set cmd="cd "_tempDir_" && "
    }
    Set cmd=cmd_sonarlint
    Set opts=""
    If $ZVersion(1)=2 Set cmd=cmd_".bat"

    Set cmd=cmd_" -X -e "

    Set tempSonarDir = ##class(%File).NormalizeDirectory(".sonarlint", tempDir)
    Do ##class(%File).CreateDirectory(tempSonarDir)

    If ($Data(^SonarLint("serverId")))&&($Data(^SonarLint("projectKey"))) {
      Set serverId = $Get(^SonarLint("serverId"))
      Set projectKey = $Get(^SonarLint("projectKey"))
      Set url = $Get(^SonarLint("url"))
      Set token = $Get(^SonarLint("token"))
      Set login = $Get(^SonarLint("login"))
      Set password = $Get(^SonarLint("password"))
      If token'="" {
        Set auth="""token"":"""_token_""""
      } Else {
        Set auth="""login"":"""_login_""",""password"":"""_password_""""
      }

      Set configFile=##class(%File).NormalizeFilename("sonarlint.json", tempDir)
      Set config = ##class(%Stream.FileCharacter).%New()
      Set config.Filename = configFile
      Do config.WriteLine("{""serverId"":"""_serverId_""", ""projectKey"": """_projectKey_"""}")
      Do config.%Save()
      Set cmd=cmd_" -u "

      Set globalConfigPath = ##class(%File).NormalizeDirectory("conf", tempSonarDir)
      Do ##class(%File).CreateDirectoryChain(globalConfigPath)
      Set globalConfigFile = ##class(%File).NormalizeFilename("global.json", globalConfigPath)
      Set globalConfig = ##class(%Stream.FileCharacter).%New()
      Set globalConfig.Filename = globalConfigFile
      Do globalConfig.WriteLine("{""servers"":[{")
      Do globalConfig.WriteLine("""id"":"""_serverId_""",")
      Do globalConfig.WriteLine("""url"":"""_url_""",")
      Do globalConfig.WriteLine(auth_"}]}")
      Do globalConfig.%Save()

      Set opts=opts_"-Duser.home="_tempDir
    }

    Set reportFile=##class(%File).NormalizeFilename("sonarReport.xml", tempSonarDir)
    Set cmd=cmd_" --xml-report "_reportFile

    If $ZVersion(1)=2 {
      Set cmd = "set SONARLINT_OPTS="_opts_"&& "_cmd_""
    } Else {
      Set cmd = "export SONARLINT_OPTS="_opts_" && "
    }

    Set logFile=tempSonarDir_"sonarlint.log"
    Set cmd=cmd_" > "_logFile_" 2>&1"

    Set sc=$Zf(-1, cmd)

    If sc'=0 {
      Set fs=##class(%Stream.FileCharacter).%New()
      Set fs.Filename=logFile
      While 'fs.AtEnd {
        Set line=fs.ReadLine()
        $$$addLine(line)
      }
      Quit
    }

    Set pat=##class(%Regex.Matcher).%New("^(\w+): ")
    If ##class(%File).Exists(logFile) {
      Set fs=##class(%Stream.FileCharacter).%New()
      Set fs.Filename=logFile
      While 'fs.AtEnd {
        Set line=fs.ReadLine()
        Write !,line
        Set pat.Text=line
        If ('pat.Locate())||(pat.Group(1)'="ERROR") {
          Continue
        }
        $$$addLine(line)
      }
      Do fs.Clear()
    }

    Set severityList=$ListBuild("blocker","critical","major","minor","info")
    Do {
      Set tSC=##class(%XML.XPATH.Document).CreateFromFile(reportFile,.tDoc)
      If $$$ISERR(tSC) Quit

      Set tSC=tDoc.EvaluateExpression("/sonarlintreport/files/file[@name="""_classFileName_"""]/issues", "issue", .tResults)
      If $$$ISERR(tSC) Quit

      For i=1:1:tResults.Count() {
        Set tRes=tResults.GetAt(i)

        While tRes.Read() {
          Set (severity,key,name,line)=""
          If tRes.NodeType="element" {
            If tRes.MoveToAttributeName("severity") { Set severity=tRes.Value }
            If tRes.MoveToAttributeName("key") { Set key=tRes.Value }
            If tRes.MoveToAttributeName("name") { Set name=tRes.Value }
            If tRes.MoveToAttributeName("line") { Set line=tRes.Value }
            If tRes.MoveToAttributeName("offset") { Set offset=tRes.Value }

            Set severityLevel=$ListFind(severityList, severity)
            If $Increment(issues(severityLevel)),$Increment(issues(severityLevel,key))
            Set issues(severityLevel,key,"name")=name
            Set issues(severityLevel,key,"lines",line)=offset
          }
        }
      }

    } While (0)
    If $$$ISERR(tSC) {
      $$$addLine($System.Status.GetErrorText(tSC))
    }

    Set tSC=##class(%Compiler.UDL.TextServices).GetTextAsArray(,className,.linesOfClass)

    Set severityLevel=""
    For {
      Set severityLevel=$Order(issues(severityLevel), 1, count)
      Quit:severityLevel=""

      $$$addLine($Justify(count,5)_" "_$ListGet(severityList, severityLevel))

      Set key=""
      For {
        Set key=$Order(issues(severityLevel, key), 1, byKeyCount)
        Quit:key=""

        Set name=issues(severityLevel, key, "name")

        $$$addLine($Justify(byKeyCount,8)_" "_name)

        If (forStudio) {
          Set line=""
          For {
            Set line=$Order(issues(severityLevel, key, "lines", line), 1, offset)
            Quit:line=""

            $$$addLine(classFileName_"(+"_line_"): "_$Get(linesOfClass(line)))
          }
        }
      }
    }
  } Catch {
  }

  If '##class(%File).RemoveDirectoryTree(tempDir) {
    Do $System.OBJ.DisplayError()
  }
  Quit $$$OK
}

}
