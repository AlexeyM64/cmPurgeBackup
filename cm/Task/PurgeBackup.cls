Include cm.Task.Purge

/// Purge backup files after Full Backup
Class cm.Task.PurgeBackup Extends %SYS.Task.Definition
{

Parameter TaskName = "cm.Task.PurgeBackup";

Parameter AllowedExtensions = ".cbk.log";

/// Number of full backup files to keep
Property FullBackupsToKeep As %Integer(MINVAL = 1) [ InitialExpression = 7 ];

/// Minimum free space in full backup directory (GB)
Property FreeSpace As %Integer(MINVAL = 0) [ InitialExpression = {..FullBackSize(2)*2} ];

/// Number of days to keep backup history (^SYS("BUHISTORY"))
Property HistoryLifeSpan As %Integer(MINVAL = 90) [ InitialExpression = 366 ];

/// File to log the results. Can be: <path>filename.log or <empty> to log to cconsole.log 
Property LogFile As %String [ InitialExpression = {..normalizeLogFile(..LogFile)} ];

/// Level of logging backup purging results (the higher, the more details
Property LogLevel As %Integer(MINVAL = 1) [ InitialExpression = 2 ];

/// Called by Task Manager
Method OnTask() As %Status [ PublicList = (flLog, flLoglevel, LogFile, rbuhistory) ]
{
	// Init
	set flLog=0 // log is not opened yet
	set (LogFile,..LogFile)=..normalizeLogFile(..LogFile)
	set flLoglevel=..LogLevel

	new $namespace set $namespace="%SYS" // We must run in %SYS
	set sc=1
	set fullbacksize=..FullBackSize(2) // call it only once
	set fb2=fullbacksize*2
	if ..FreeSpace < fb2 set ..FreeSpace=fb2
	set cbkfiles="^||c"
 	kill @cbkfiles
	
	do ..log("Purge Backup v. "_$$$VERSION_" --  Started: "_$zdate($horolog, 2)_" "_$ztime($piece($horolog,",",2)))
	set sc=..DirsFromSYS(.cbkdirs, .untouch, .fullbackdir, ..HistoryLifeSpan, .sdatelastfull, .stophistdate)
	if 'sc do ..log("DirsFromSYS -- "_$system.Status.GetErrorText(sc)) goto onq

	set sc=..DirsSchedSpace(.cbkdirs, .free) // check free space in the directories of scheduled backup tasks
	if 'sc do ..log("DirsSchedSpace -- "_$system.Status.GetErrorText(sc)) goto onq
	if sc do ..log("DirsSchedSpace -- Backup tasks directory(ies). Currently free = "_free_" GB")
	
	set sc=..DirsFiles(.cbkdirs, "DateModified", cbkfiles, sdatelastfull, .untouch)
	if 'sc do ..log("DirsFiles -- "_$system.Status.GetErrorText(sc)) goto onq
	
	set nBack=..FullBackupsToKeep

	set nDel=0
	do {
		set free0=free
		do ..log("FilesDel -- FullBackupsToKeep = "_nBack_", wanted FreeSpace = "_..FreeSpace_" GB", 2) // assumed wantings on the 1st iteration
		set nDel0=nDel,sc=..FilesDel(cbkfiles, nBack, .untouch, .nDel, .nBackKept, stophistdate, 1) // bDelete=1 - really delete files
		if 'sc do ..log("FilesDel -- "_$system.Status.GetErrorText(sc)) goto onq
		do ..log("FilesDel -- "_(nDel-nDel0)_" backup file(s) deleted, "_nBackKept_" full backups kept", 3) // lifted to debug log level
		kill cbkdirssched set sc=..DirsSchedSpace(.cbkdirssched, .free) // check free space in the directories of scheduled backup tasks
		if 'sc do ..log("DirsSchedSpace -- "_$system.Status.GetErrorText(sc)) goto onq
		do ..log("DirsSchedSpace -- Backup tasks directory(ies). Currently free = "_free_" GB", 3) // lifted to debug log level

		if (free < ..FreeSpace) {
			set nBack=nBack-1 // delete additional files one by one;
			do ..log("fullbacksize="_fullbacksize_" nBackKept="_nBackKept_" FullBackupsToKeep(nBack)="_nBack, 3)
		}
		// nDel is total, nBackKept is the last result, and it's OK
	} while ( (free<..FreeSpace) && (nBack>0) ) // if low space, loop ..FilesDel() till nBack=0
onq
	do ..log("Purge Backup v. "_$$$VERSION_" -- Finished: "_$zdate($horolog, 2)_" "_$ztime($piece($horolog,",",2))_$select($get(free)>0:"  Currently free = "_free_" GB;  "_$get(nDel,"?")_" backup file(s) deleted, "_$get(nBackKept,"?")_" full backup(s) kept", 1:""))
	quit sc
}

/// Apply protocol file name restrictions
ClassMethod normalizeLogFile(pLogFile) As %String [ PublicList = (flLog, flLoglevel, LogFile) ]
{
	if $extract(pLogFile)="^" set pLogFile=""
	if pLogFile="" goto ckLogQ
	set pLogFile=##class(%File).NormalizeFilename(pLogFile)
	if $zconvert(##class(%File).GetFilename(pLogFile),"L")="cconsole.log" {
		set pLogFile="" goto ckLogQ
	}
	set LogDir=##class(%File).GetDirectory(pLogFile)
	set rc=1
	if '##class(%File).Exists(LogDir) set rc=##class(%File).CreateDirectoryChain(LogDir, .return)
	set pLogFile=$select(rc:LogDir_"purgeback.log", 1:"")
ckLogQ
	;set LogFile=pLogFile
	quit pLogFile
}

/// Collect backup and log directories from ^SYS
/// <br>In:
/// <br>nHist history life span; older entries are killed (after processing)
/// <br>Out:
/// <br>cbkdirs - normalized dirs collected from "^SYS(""BACKUP"",""LASTFULL"")" and "^SYS(""BUHISTORY"")".
/// <br>untouch - normalized file names of files younger (and including) the LASTFULL backup
/// <br>fullbackdir - normalized LASTFULL backup dir
ClassMethod DirsFromSYS(ByRef cbkdirs, ByRef untouch, ByRef fullbackdir, nHist As %Integer, ByRef sdatelastfull, ByRef stophistdate) As %Status [ Private, PublicList = (flLog, flLoglevel, LogFile, rbuhistory) ]
{
 set sc=1

 // get LASTFULL backup file and log directories and mark them untouchable
 set rlastfull=$name(^SYS("BACKUP","LASTFULL"))
 set rbuhistory=$name(^SYS("BUHISTORY"))
 
 set file=$get(@rlastfull@("DEVICE")),hdate=$get(@rlastfull@("DATE")),log=$get(@rlastfull@("LOG"))
 if (file="") || (hdate="") {
 	set mess="Full Backup was never performed" do ..log(mess)
 	set sdatelastfull=0
 	set sc=$system.Status.Error(5001, mess)
 	goto dirsysq
 }
 do ..log("DirsFromSYS -- LASTFULL: "_$zdate(hdate,3)_" "_$ztime($piece(hdate,",",2))_"~"_file, 2)
 
 set fullbackdir=##class(%File).NormalizeDirectory(##class(%File).GetDirectory(file,1))
 if fullbackdir=$zutil(12) set fullbackdir=$$$DEFBACKUPDIR // Use default backup dir $$$DEFBACKUPDIR whenever empty dir is met
 set fullbackdir=##class(%File).NormalizeDirectory(fullbackdir)

 set sdatelastfull=$$$HTOSDATE(hdate)
 for ifile=log, file {  // (log, file) vs (file,log) to save untouch(log) always
	if ifile="" continue
 	if ifile=file {
	 	kill info
		set info("date")=$zdatetime(hdate,3,1)
 		set info("sdate")=$$$HTOSDATE(hdate)
		set sc=..GetFileData(file, .info)
		if 'sc do ..log("DirsFromSYS -- GetFileData:"_$system.Status.GetErrorText(sc))
 		set ifile=##class(%File).NormalizeFilename(ifile)
 		if sc,info("status")="Completed" {  // Completed LastFull is untouchable!
	  		set untouch(ifile)=""
	  		do ..log("DirsFromSYS -- LASTFULL: added to untouch "_ifile, 3)
	  	}
 	} else {
	 	set untouch(ifile)="" // log is untouchable anyway
 	}
 }

 // process backup history
 
 set stophistdate=hdate-nHist // to clear the history

 set sdate=$order(@rbuhistory@(""),-1) // starting point

 // skip all backups till stophistdate
 while (sdate '= "") {
	// take in account all backups
	set hdate=$$$HFROMSDATE(sdate)
	set file=$get(@rbuhistory@(sdate,"DEVICE"))
	set log=$get(@rbuhistory@(sdate,"LOG"))
	;s status=$g(@rbuhistory@(sdate,"STATUS"))
	for ifile=log, file {
		if ifile="" continue
 		if sdate > sdatelastfull { // we don't expect that new directories were added, so unneed to mark as untouchable as it will do ..DirsFiles
 		} elseif ##class(%File).Exists(ifile) {
			set cbkdir=##class(%File).NormalizeDirectory(##class(%File).GetDirectory(ifile,1))
			if cbkdir=$zutil(12) set cbkdir=$$$DEFBACKUPDIR // Use default backup dir $$$DEFBACKUPDIR whenever empty dir is met
			do ..AddToCbkDirs(.cbkdirs, .cbkdir)
 		} else {
	 		// don't log "does not exist" files access errors for files collected from backup history
 		}

 	}
    if hdate < stophistdate kill @rbuhistory@(sdate) // kill buhistory older than stophistdate
	set sdate=$order(@rbuhistory@(sdate),-1)
 }
 
 // get dirs from ^SYS("BACKUPTASK") (SMP/Operations - Backup - "task" definitions)
 set ref=$name(^SYS("BACKUPTASK"))
 set x="" for {
 	set x=$order(@ref@(x)) quit:x=""
 	set cbkdir=$piece($piece(@ref@(x),"^",3),",")
 	if cbkdir="" set cbkdir=$$$DEFBACKUPDIR // Use default backup dir $$$DEFBACKUPDIR whenever empty dir is met
 	do ..AddToCbkDirs(.cbkdirs, .cbkdir)
 }
 
dirsysq
 quit sc
}

/// Adds to cbkdirs backup dirs fetched from the task schedule and calculate free and total space in MB for each directory in <cbkdirs>
/// <br>cbkdirs(dir)=free~total
/// <br>exclude dirs with error(s) from cbkdirs
/// <br>Returns maxfree space in scheduled backup tasks' directories
ClassMethod DirsSchedSpace(ByRef cbkdirs, ByRef maxfree) As %Status [ Private, PublicList = (flLog, flLoglevel, LogFile) ]
{
 // get task list
 set sc=1
 set rset = ##class(%ResultSet).%New("%SYS.Task:TaskListDetail")
 set sc=rset.Execute() if 'sc goto frq
 SET columns = rset.GetColumnCount()
 // Now fetch the results
 kill tasks
 WHILE rset.Next() {
    set class=rset.Data("TaskClass")
    if $extract(class,1,$length("%SYS.Task.Backup"))="%SYS.Task.Backup" set tasks($increment(tasks))=rset.Data("ID")
 }
 do rset.Close()
 set maxfree=0
 for i=1:1:$get(tasks) {
	 set ID=tasks(i)
	 set oref=##class(%SYS.Task).%OpenId(ID)
	 if $isobject(oref) {
		 set sc=oref.GetSettings(.settings) if 'sc goto frq
		 set cbkdir=$listget(settings,$listfind(settings,"Device")+1)
		 if cbkdir="" set cbkdir=$$$DEFBACKUPDIR // Use default backup dir $$$DEFBACKUPDIR whenever empty dir is met
		 set free=..AddToCbkDirs(.cbkdirs, .cbkdir)
		 if free>0 {
			set:free>maxfree maxfree=free
		 } else {
		 }
	 }
 }
frq 
 quit sc
}

/// Collect files from cbkdirs, sorted by date criteria, into @cbkfiles, in reverted sort order.
/// <br>NB: DateModified is the default sort criteria, as не меняется при копировании и она в заголовке файла (хотя в BUHISTORY пишется DateCreated)
/// <br>в Linux, если файл не копировался, даты совпадают.
ClassMethod DirsFiles(ByRef cbkdirs, datecrit = "DateModified", cbkfiles, sdatelastfull, ByRef untouch) As %Status [ Private, PublicList = (flLog, flLoglevel, LogFile, datecrit) ]
{
 //query FileSet(directory As %String(MAXLEN=""), wildcards As %String, sortby As %String = "", includedirs As %Boolean = 0, delimiter As %String = ";")
 //Selects Name As %String, Type As %String, Size As %BigInt, DateCreated As %TimeStamp, DateModified As %TimeStamp, ItemName As %String
 //
 set sc=0, rc=$$$ERROR(5001,"Unknown Error")
 set dirU=""
 for  {
  set dir=..NextCbkDir(.cbkdirs, .dirU) quit:dir=""
  set rset = ##class(%ResultSet).%New("%File:FileSet")
  set rc=rset.Execute(dir,,datecrit) if 'rc do ..log("DirsFiles -- "_dir_" : "_$system.Status.GetErrorText(rc)) continue // only log directory access errors, not quitting
  set columns = rset.GetColumnCount()
  // Now fetch the results
  while rset.Next() {
	if (rset.Data("Type") '= "F") continue // it's not a file ("F" means "File")
	kill fdata
	set fdata("date")=rset.Data(datecrit)
	set fdata("sdate")=$$$HTOSDATE($zdatetimeh(fdata("date"),3,1))
	set rc=..GetFileData(rset.Data("Name"), .fdata)
	if 'rc do ..log("DirsFiles -- GetFileData: "_$system.Status.GetErrorText(rc)) continue
      set sdate=fdata("sdate")
           // >= sdatelastfull: to put last full into cbkfiles
  	if sdate>=sdatelastfull&&(fdata("status")="Completed") { // completed files younger than the LASTFULL are untouchable as well;
		set untouch(fdata("file"))=""
		do ..log("DirsFiles -- added to untouch "_fdata("file"), 3)
  	} elseif fdata("status")="Failed" { // exclude files with _known_ failed status
  		set sdate=sdatelastfull-1000000
  	}
	while $data(@cbkfiles@(sdate)) { set sdate=sdate+0.1 }
	merge @cbkfiles@(sdate)=fdata
	do ..log("DirsFiles -- added to cbkfiles "_fdata("file")_" with status="_fdata("status")_" using sdate="_sdate, 3)
	set sc=1
  } 
  do rset.Close()
 }
 quit $select(sc:sc, 1:rc)
}

/// Create cbkdirs(cbkdirU)=cbkdir_"~"_free(GB)_"~"_total(GB); return free (or 0, if not exists or non-accessible)
/// e.g. s free=..AddToCbkDirs(.cbkdirs, .cbkdir)
ClassMethod AddToCbkDirs(ByRef cbkdirs, ByRef cbkdir) As %Numeric [ Private ]
{
	set cbkdir=##class(%File).NormalizeDirectory(cbkdir)
	set cbkdirU=$select($zversion(1)=2:$zconvert(cbkdir,"U"),1:cbkdir)
	set free=0
	if $data(cbkdirs(cbkdirU)) {
		set free=$piece(cbkdirs(cbkdirU),"~",2)
	} else {
		if ##class(%File).Exists(cbkdir) {
		   set sc=..GetDirectorySpace(cbkdir, .free, .total, 2)
		   if sc {
				set cbkdirs(cbkdirU)=cbkdir_"~"_free_"~"_total
		   } else {
				do ..log("AddToCbkDirs -- GetDirectorySpace of "_cbkdir_" -- "_$system.Status.GetErrorText(sc))
		   }
		} else {
			do ..log("AddToCbkDirs -- "_cbkdir_" does not exist") 
		}
	}
	quit free
}

/// Get next cbkdir from cbkdirs(cbkdirU)
/// <br> e.g. s cbkdir=..NextCbkDir(.cbkdirs, .cbkdirU)
ClassMethod NextCbkDir(ByRef cbkdirs, ByRef cbkdirU) As %String [ Private ]
{
	set cbkdirU=$order(cbkdirs(cbkdirU))
	set cbkdir=$piece(cbkdirU,"~")
	quit cbkdir
}

/// Get file data into fdata (sdate, date, type)
/// <br> .cbk - (type of backup, status, log, sdate, date, file) from file header (de! now getting from name!)
/// <br> .log - (type="Log")
/// <br> .else -(type="")
ClassMethod GetFileData(file, ByRef fdata) As %Status [ Private, PublicList = (datecrit, rbuhistory) ]
{
	set sc=1
	; k fdata // don't kill as there are some values already exist
	set fdata("type")=""
	set fdata("status")=""
	set fdata("log")=""
	set fdata("file")=##class(%File).NormalizeFilename(file) // maybe does not needed
	set filelow=$zconvert(file,"L")
	set extlow=$piece(filelow,".",$length(filelow,"."))
	if '$find(..#AllowedExtensions_".", extlow_".") set sc=$system.Status.Error(5001,"Skipped "_file_" : not allowed extension") goto getfq
	if extlow="cbk" {
		set oStr=$$$STREAMFB.%New()
  		set oStr.Filename=file
  		set len=$zhex("404"), hdr1=oStr.Read(.len, .sc) if 'sc goto getfq
  		set (len0,len)=$zhex("600")-$zhex("404"), hdr1=oStr.Read(.len) if 'sc goto getfq
  		set type=$piece(hdr1,$char(0),7)
  		if len=len0 && ((type="Full") || (type="Incremental") || (type="Cumulative Incremental")) {
  			set fdata("type")=type
  			set hdt=$piece(hdr1,$char(0),8)
  			try {
	  			set fdata("sdate")=$$$HTOSDATE(hdt)
	  			set fdata("status")=$get(@rbuhistory@(fdata("sdate"),"STATUS"),"Unknown")
  				set fdata("date")=$zdate(hdt,3)_" "_$ztime($piece(hdt,",",2),1)
  			} catch { // corrupted date filed
  				set fdata("status")="Corrupted Date Filed "_$get(hdt)_" : "_$zerror
  				set sc=$$$ERROR(5001,fdata("status"))
  			}
  		} else { // corrupted backup type filed (?)
  			set fdata("type")=$select($find(filelow,"full"):"Full",$find(filelow,"cum"):"Cumulative Incremental",$find(filelow,"inc"):"Incremental",1:"")
  			set fdata("status")="Wrong File Type "_filelow
  			set sc=$$$ERROR(5001,fdata("status"))
		}
	} elseif extlow="log" {
		set fdata("type")="Log"
		set fdata("status")="Log"
	}
getfq
	quit sc
}

/// Purge files in @cbkfiles, saving only 1st nBack full backup files (and all "younger" files of any type)
/// <br>If fdata("log")'="", delete log file (may be useful as log files may be stored in the directory not listed in cbkdirs)
/// <br>Out: nDel - number of deleted files
ClassMethod FilesDel(cbkfiles, nBack, ByRef untouch, ByRef nDel, ByRef nBackKept, stophistdate, bDelete) As %Status [ Private, PublicList = (flLog, flLoglevel, LogFile) ]
{
 set sc=1
 set msdate=""
 set nBackKept=0
 set rbuhistory=$name(^SYS("BUHISTORY"))
 for  {
    set msdate=$order(@cbkfiles@(msdate),-1) quit:msdate=""
    merge fdata=@cbkfiles@(msdate)
    set file=fdata("file")
    set filename=##class(%File).GetFilename(file)
    set type=fdata("type")
    set status=fdata("status")
    set log=fdata("log")
    set sdate=fdata("sdate")
    set date=fdata("date")
    set hdate=$$$HFROMSDATE(sdate)
    if ( nBack > 0 ) {
	   if (type'="Log") {
		do ..log("FilesDel -- Passed  "_date_"~"_file_"~"_status_"~"_type, 2) // don't log passing "Log"s
	  	if (type="Full") { set nBackKept=nBackKept+1 set nBack=nBack-1 } // one more Full backup was passed by
	   }
    } elseif '$data(untouch(file)) {
	   if type'="Log" || (hdate<stophistdate) {  // delete all Logs older than stophistdate and all files of other type
    	       if ##class(%File).Exists(file) && ##class(%File).Delete(file), $increment(nDel) {
			do ..log("FilesDel -- Deleted "_date_"~"_file_"~"_status_"~"_type, 2)
			if $data(@rbuhistory@(sdate)) {
				if type="Log" { set @rbuhistory@(sdate,"LOG")="" }
				else              { set @rbuhistory@(sdate,"DEVICE")="" }
			 }
		 } elseif '##class(%File).Exists(file) {
			do ..log("FilesDel -- File not exists "_date_"~"_file, 2)
		 } else {
			do ..log("FilesDel -- File delete failure "_date_"~"_file)
		 }
		 kill @cbkfiles@(msdate)
	   } else {
	   	if type'="Log" do ..log("FilesDel -- Unknown reason for passing "_date_"~"_file_"~"_status_"~"_type, 3)
	   }
	} else {
	   if type'="Log" set nBackKept=nBackKept+1 do ..log("FilesDel -- Untouch "_date_"~"_file_"~"_status_"~"_type, 2) // don't log untouch 'Log's
	}
 }
 quit sc
}

/// Log method
/// <br>flLog=0 log is not initialized, =1 log to file, ;=2 log to global;, -1 log to cconsole.log
/// <br>level - severity level of the message; if level<=flLoglevel, mess is logged. ;;; Private
ClassMethod log(mess = "", level = 1) [ PublicList = (flLog, flLoglevel, LogFile) ]
{
	set zzzWHO=..#TaskName
	if '$g(flLog) {
		if LogFile'="" && ($extract(LogFile)'="^") && '$find(LogFile,"cconsole.log") { open LogFile:("NW"):3 set flLog=1 else  set flLog=-1 }
		elseif $extract(LogFile)="^" { set LogFile="",flLog=-1 } ; s flLog=2, LogFile="^%zPurgeBackup" k @LogFile }
		else { set flLog=-1 }
	}
	if level <= $g(flLoglevel,2) {
		if flLog=1 { use LogFile write mess,! }
		; elseif flLog=2 { s @LogFile@($i(@LogFile))=mess }
		else { $$$CLOG(mess) }
	}
}

/// Estimates backup size in GB for backup of type 1=INCR 2=FULL 3=CUM.INCR ;calculate full backup size basing on DBs size
ClassMethod FullBackSize(type = 2) As %Integer
{
	new $namespace set $namespace="%SYS"
	if type'=2 set info=$$INT^DBSIZE(type),bckSize=$fnumber($piece(info,"^",5)/1024/1024/1024,"",3) goto fullBackSizeQ
	set rs=##class(%ResultSet).%New("Backup.General:DatabaseList")
	set bckSize=0
	do rs.Execute()
	while rs.Next() { 
		set dir=rs.Data("Directory")
		set sc=##Class(SYS.Database).%OpenId(dir).GetFreeSpace(dir,.freeSpace,.fb)
		if sc set bckSize = bckSize + ##Class(SYS.Database).%OpenId(dir).Size - freeSpace
	}
	do rs.Close()
	set bckSize=$fnumber(bckSize/1024,"",3) // GB
fullBackSizeQ
	quit bckSize
}

/// Return the amount of total space and free space in either Bytes,MB,GB on a drive or directory
/// <br>Stolen from %Library.File. Corrections:
/// <br>- Don't fork the code for Windows as it runs correct for both platforms.
/// <br>- precision up to 3d digit after decimal point (xxxx.yyy MB)
/// <br>
/// Name = Valid Drive or directory specification<br>
/// Flag = 0 - Return bytes<br>
/// Flag = 1 - Return MB (Default)<br>
/// Flag = 2 - Return GB<br>
/// <br>
/// MB and GB returned are rounded to 2 decimal places.<br>
/// Any error status returned is O/S level error.
ClassMethod GetDirectorySpace(Name As %String, ByRef FreeSpace As %String, ByRef TotalSpace As %String, Flag As %Integer = 1) As %Status
{
	If $get(Name)="" Set Name=$zutil(168)
	Set $ztrap="Error"
	Set FreeSpace=0,TotalSpace=0
	Set Status=$zutil(140,13,Name)
	If +Status<0 Quit $$$ERROR($$$ErrorCodeIs,$zabs(Status))
	Set BlockSize=$piece(Status,",",4)
	Set FreeSpace=$piece(Status,",",1)*BlockSize // Don't fork the code for Windows as it runs correct for both platforms
	Set TotalSpace=$piece(Status,",",3)*BlockSize
	If Flag=1 Set Div=1024*1024
	If Flag=2 Set Div=1024*1024*1024
	If Flag'=0 {
		Set FreeSpace=$fn(FreeSpace/Div,"",3) // precision up to 3d digit after decimal point
		Set TotalSpace=$fn(TotalSpace/Div,"",3)
	}
	Quit $$$OK
Error Set $ztrap=""
	Quit $$$ERROR($$$CacheError,$zerror)
}

}

