# cmPurgeBackup
 [![Quality Gate Status](https://community.objectscriptquality.com/api/project_badges/measure?project=intersystems_iris_community%2FcmPurgeBackup&metric=alert_status)](https://community.objectscriptquality.com/dashboard?id=intersystems_iris_community%2FcmPurgeBackup)

cmPurgeBackup is an utility that can be used to erase old InterSystems IRIS/Caché/Ensemble Online Backup files. It runs as a Task Manager task. It is fully compatible with all predefined classes of backup tasks, such as FullDBList, IncrementalDBList, etc., and it does not require any changes to the code that is used in these tasks.

Objectscript contest template was used;
[Topic and Terms](https://community.intersystems.com/post/join-online-programming-contest-intersystems-iris-docker-and-objectscript).

## Prerequisites
Make sure you have [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git) and [Docker desktop](https://www.docker.com/products/docker-desktop) installed.

## Installation with ZPM

zpm:USER>install cmpurgebackup

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
You will notice two custom tasks: FullDBList and cmPurgeBackup. The first is scheduled to run on demand, the latter - to run on FullDBList completion.

Current setting of cmPurgeBackup is to leave the last Full Backup file (.cbk) only; you may change it if you wish. Possible task's settings are discussed in the correspondent [Developer Community article](https://community.intersystems.com/post/cmpurgebackup-useful-add-iriscach%C3%A9-online-backup).

## Have fun!
