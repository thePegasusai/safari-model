@rem
@rem Copyright 2015 the original author or authors.
@rem
@rem Licensed under the Apache License, Version 2.0 (the "License");
@rem you may not use this file except in compliance with the License.
@rem You may obtain a copy of the License at
@rem
@rem      https://www.apache.org/licenses/LICENSE-2.0
@rem
@rem Unless required by applicable law or agreed to in writing, software
@rem distributed under the License is distributed on an "AS IS" BASIS,
@rem WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
@rem See the License for the specific language governing permissions and
@rem limitations under the License.
@rem

@if "%DEBUG%"=="" @echo off
@rem ##########################################################################
@rem
@rem  Gradle startup script for Windows
@rem
@rem ##########################################################################

@rem Set local scope for the variables with windows NT shell
if "%OS%"=="Windows_NT" setlocal

set DIRNAME=%~dp0
if "%DIRNAME%"=="" set DIRNAME=.
@rem This is normally unused
set APP_BASE_NAME=%~n0
set APP_HOME=%DIRNAME%

@rem Validate Java installation and version
call :validate_java
if errorlevel 1 (
    echo Error: Java validation failed. Ensure Java 17 or higher is installed and JAVA_HOME is correctly set.
    exit /b 1
)

@rem Add default JVM options here. You can also use JAVA_OPTS and GRADLE_OPTS
@rem to pass JVM options to this script.
set DEFAULT_JVM_OPTS="-Xmx64m" "-Xms64m" "-Dfile.encoding=UTF-8"

@rem Find java.exe
if defined JAVA_HOME goto findJavaFromJavaHome

echo Error: JAVA_HOME is not set and no 'java' command could be found in your PATH.
echo Please set the JAVA_HOME variable in your environment to match the
echo location of your Java installation.
exit /b 1

:findJavaFromJavaHome
set JAVA_HOME=%JAVA_HOME:"=%
set JAVA_EXE=%JAVA_HOME%/bin/java.exe

if exist "%JAVA_EXE%" goto init

echo Error: JAVA_HOME is set to an invalid directory: %JAVA_HOME%
echo Please set the JAVA_HOME variable in your environment to match the
echo location of your Java installation.
exit /b 1

:init
@rem Configure Gradle specific environment variables
if not defined GRADLE_USER_HOME set GRADLE_USER_HOME=%USERPROFILE%\.gradle

@rem Configure memory and encoding options for Gradle
set GRADLE_OPTS=-Dorg.gradle.jvmargs=-Xmx2048m -XX:MaxPermSize=512m -XX:+HeapDumpOnOutOfMemoryError -Dfile.encoding=UTF-8 %GRADLE_OPTS%

@rem Handle proxy settings if defined
if defined HTTP_PROXY (
    set GRADLE_OPTS=%GRADLE_OPTS% -Dhttp.proxyHost=%HTTP_PROXY% -Dhttp.proxyPort=80
)
if defined HTTPS_PROXY (
    set GRADLE_OPTS=%GRADLE_OPTS% -Dhttps.proxyHost=%HTTPS_PROXY% -Dhttps.proxyPort=443
)
if defined NO_PROXY (
    set GRADLE_OPTS=%GRADLE_OPTS% -Dhttp.nonProxyHosts=%NO_PROXY%
)

@rem Get command-line arguments, handling Windows variants
set CMD_LINE_ARGS=
set _SKIP=2

:win9xME_args_slurp
if "x%~1" == "x" goto execute

set CMD_LINE_ARGS=%*

:execute
@rem Setup the command line
set CLASSPATH=%APP_HOME%\gradle\wrapper\gradle-wrapper.jar

@rem Execute Gradle
"%JAVA_EXE%" %DEFAULT_JVM_OPTS% %JAVA_OPTS% %GRADLE_OPTS% "-Dorg.gradle.appname=%APP_BASE_NAME%" -classpath "%CLASSPATH%" org.gradle.wrapper.GradleWrapperMain %CMD_LINE_ARGS%

:end
@rem End local scope for the variables with windows NT shell
if %ERRORLEVEL% equ 0 goto mainEnd
echo Error: Gradle execution failed with exit code %ERRORLEVEL%
exit /b %ERRORLEVEL%

:mainEnd
if "%OS%"=="Windows_NT" endlocal

:omega

@rem -----------------------------------------------------------------------
@rem Function to validate Java installation and version
:validate_java
if not defined JAVA_HOME (
    echo Error: JAVA_HOME environment variable is not set
    exit /b 1
)

"%JAVA_HOME%\bin\java.exe" -version 2>&1 | findstr /i "version" | findstr /i "17\." > nul
if errorlevel 1 (
    echo Error: Java 17 or higher is required
    exit /b 1
)

exit /b 0