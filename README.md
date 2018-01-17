# AWS Glacier upload script - aws-glacier-multipart-upload-script

A shell script to upload via multipart-upload files to Glacier.
Main purpose of this (collection) of scripts is to use the AWS Glacier multipart upload functionality via the shell for all files in a specified folder.


### Installation

Just upload the files to your server and give them executional rights.

In order to use the scripts you will need a valid AWS Glacier account and to install [aws-cli](https://docs.aws.amazon.com/cli/latest/userguide/installing.html) and [Java JRE](https://www.java.com/en/download/help/linux_install.xml).
Please follow the instructions depending on your OS.

### Usage
```sh
$ cd PATH
$ ./glacierMultiAll.sh
```
