Class %z.Installer
{

XData setup
{
<Manifest>
  <Default Name="SourceDir" Value="#{$system.Process.CurrentDirectory()}"/>
  <Default Name="Namespace" Value="IRISAPP"/>
  <Default Name="app" Value="irisapp" />

  <Namespace Name="${Namespace}" Code="${Namespace}" Data="${Namespace}" Create="yes" Ensemble="no">

    <Configuration>
      <Database Name="${Namespace}" Dir="/opt/${app}/data" Create="yes" Resource="%DB_${Namespace}"/>

      <Import File="${SourceDir}src" Flags="ck" Recurse="1"/>
    </Configuration>
    <CSPApplication Url="/csp/${app}" Directory="${cspdir}${app}"  ServeFiles="1" Recurse="1" MatchRoles=":%DB_${Namespace}" AuthenticationMethods="32"
       
    />
    
    <!-- Import tasks -->
 <If Condition='#{##class(%File).Exists("${SourceDir}/tasks.xml")}'>
<Log Level="0" Text="Tasks will be imported from ${SourceDir}tasks.xml" />
  <Invoke Class="%z.Installer" Method="TasksImportAndSchedule" CheckStatus="1">
   <Arg Value="${SourceDir}tasks.xml"/>
   <Arg Value="${Namespace}"/>
  </Invoke>
 </If>
    
  </Namespace>

</Manifest>
}

ClassMethod setup(ByRef pVars, pLogLevel As %Integer = 3, pInstaller As %Installer.Installer, pLogger As %Installer.AbstractLogger) As %Status [ CodeMode = objectgenerator, Internal ]
{
  #; Let XGL document generate code for this method. 
  Quit ##class(%Installer.Manifest).%Generate(%compiledclass, %code, "setup")
}

ClassMethod TasksImportAndSchedule(pFile, pNamespace) As %Status
{
  s scImport=##class(%SYS.Task).ImportTasks(pFile)
  ;if 'scImport g TIASq
  Set Rset=##class(%ResultSet).%New("%SYS.Task:QuickTaskList") // to activate imported schedule we must rewrite each task
  Do Rset.Execute()
  while Rset.Next() {
	  if Rset.Data("ID")>999 {
	    s tid=Rset.Data("ID")
	    s refT=##class(%SYS.Task).%OpenId(tid)
	    ;useless because if NameSpace does not exist, task won't be imported;
	    ;if refT.NameSpace'="%SYS" s refT.NameSpace=pNamespace
	    s sc=refT.%Save()
	    if 'sc g TIASq
       }
  }
TIASq
  if $g(Rset)'="" Do Rset.Close()
  q $$$ADDSC(scImport,sc)
}

/// Invoke the installer passing in some variables
/// zn "%SYS" s sc=##class(%z.Installer).RunInstall() zw sc
ClassMethod RunInstall() As %Status
{
	#dim tVars
	#dim tStatus As %Status
	#dim tLogLevel As %Integer = 1
	
	// Initialize any variables we want to pass to the installer; don't forget to duplicate the change in RunInstallWithLog()!
	Set tVars("SourceDir") = "/irisdev/app/cmPurgeBackup/" ;$system.Process.CurrentDirectory()
	Set tVars("Namespace") = "IRISAPP1"
	
	// Invoke the installer
	Set tStatus = ..setup(.tVars,tLogLevel)
	
	Do:$$$ISERR(tStatus) $system.OBJ.DisplayError(tStatus)
	
	Quit tStatus
}

}

