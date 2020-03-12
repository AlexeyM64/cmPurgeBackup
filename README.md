# cmPurgeBackup
cmPurgeBackup is an utility that can be used to erase old InterSystems IRIS/Caché/Ensemble Online Backup files. It runs as a Task Manager task. It is fully compatible with all predefined classes of backup tasks, such as FullDBList, IncrementalDBList, etc., and it does not require any changes to the code that is used in these tasks.

objectscript-contest-template was used 
[Topic and Terms](https://community.intersystems.com/post/join-online-programming-contest-intersystems-iris-docker-and-objectscript)

## Prerequisites
Make sure you have [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git) and [Docker desktop](https://www.docker.com/products/docker-desktop) installed.

## Installation 

1. Open terminal and clone/git pull the repo into any local directory

```
$ git clone https://github.com/AlexeyM64/cmPurgeBackup.git
```

2. In the same terminal run:

```
$ cd cmPurgeBackup; docker-compose build
```

3. Run the IRIS container:

```
$ docker-compose up -d
```

## How to Run the Application

Point your browser to System Management Portal and go to System > Task Manager > Task Schedule.
You will notice two custom tasks: FullDBList and cmPurgeBackup. The latter is scheduled on FullDBList comletetion. Current setting is to leave the last Full Backup file (.cbk) only, you may change it editing the cmPurgeBackup task settings.

## Have fun!
