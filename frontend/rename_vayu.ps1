Get-ChildItem -Path lib,test,integration_test -Include *.dart -Recurse | ForEach-Object { (Get-Content $_.FullName) -replace 'package:vayug/', 'package:vayug/' | Set-Content $_.FullName }
