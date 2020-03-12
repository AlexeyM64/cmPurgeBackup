ROUTINE cm.Task.Purge [Type=INC]
#define VERSION "2.6.21"

/// Date conversion macro: $h datetime to sdate (datetime -> datetime)
#define HTOSDATE(%1) $tr($j($p(%1,","),5)_$j($p(%1,",",2),6)," ",0)

/// Date conversion macro: hdate from sdate (datetime -> date)
#define HFROMSDATE(%1) $e(%1,1,5)

#define DEFBACKUPDIR $zu(12)_"Backup"

/// Version independent File Binary Stream
#if $$$CacheVersion>2008.1
  #define STREAMFB ##class(%Stream.FileBinary)
#else
  #define STREAMFB ##class(%FileBinaryStream)
#endif

#DEFINE CLOG(%1) d $zu(9,"","(***) "_$g(zzzWHO)_": "_%1)

