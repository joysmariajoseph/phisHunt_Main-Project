# Copyright (c) 2014 Microsoft Corp.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

Function ConvertTo-HashTable {
    <#
    .Synopsis
        Convert an object to a HashTable
    .Description
        Convert an object to a HashTable excluding certain types.  For example, ListDictionaryInternal doesn't support serialization therefore
        can't be converted to JSON.
    .Parameter InputObject
        Object to convert
    .Parameter ExcludeTypeName
        Array of types to skip adding to resulting HashTable.  Default is to skip ListDictionaryInternal and Object arrays.
    .Parameter MaxDepth
        Maximum depth of embedded objects to convert.  Default is 4.
    .Example
        $bios = get-ciminstance win32_bios
        $bios | ConvertTo-HashTable
    #>
    
    Param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [Object]$InputObject,
        [string[]]$ExcludeTypeName = @("ListDictionaryInternal","Object[]"),
        [ValidateRange(1,10)][Int]$MaxDepth = 4
    )

    Process {

        Write-Verbose "Converting to hashtable $($InputObject.GetType())"
        #$propNames = Get-Member -MemberType Properties -InputObject $InputObject | Select-Object -ExpandProperty Name
        $propNames = $InputObject.psobject.Properties | Select-Object -ExpandProperty Name
        $hash = @{}
        $propNames | % {
            if ($InputObject.$_ -ne $null) {
                if ($InputObject.$_ -is [string] -or (Get-Member -MemberType Properties -InputObject ($InputObject.$_) ).Count -eq 0) {
                    $hash.Add($_,$InputObject.$_)
                } else {
                    if ($InputObject.$_.GetType().Name -in $ExcludeTypeName) {
                        Write-Verbose "Skipped $_"
                    } elseif ($MaxDepth -gt 1) {
                        $hash.Add($_,(ConvertTo-HashTable -InputObject $InputObject.$_ -MaxDepth ($MaxDepth - 1)))
                    }
                }
            }
        }
        $hash
    }
}

Function Start-HTTPListener {
    <#
    .Synopsis
        Creates a new HTTP Listener accepting PowerShell command line to execute
    .Description
        Creates a new HTTP Listener enabling a remote client to execute PowerShell command lines using a simple REST API.
        This function requires running from an elevated administrator prompt to open a port.

        Use Ctrl-C to stop the listener.  You'll need to send another web request to allow the listener to stop since
        it will be blocked waiting for a request.
    .Parameter Port
        Port to listen, default is 8888
    .Parameter URL
        URL to listen, default is /
    .Parameter Auth
        Authentication Schemes to use, default is IntegratedWindowsAuthentication
    .Example
        Start-HTTPListener -Port 8080 -Url PowerShell
        Invoke-WebRequest -Uri "http://localhost:8888/PowerShell?command=get-service winmgmt&format=text" -UseDefaultCredentials | Format-List *
    #>
    
    Param (
        [Parameter()]
        [Int] $Port = 8888,

        [Parameter()]
        [String] $Url = "validate"
        )
    Process {
        $ErrorActionPreference = "Stop"
	Add-Type -AssemblyName System.Web
        $CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal( [Security.Principal.WindowsIdentity]::GetCurrent())
        if ( -not ($currentPrincipal.IsInRole( [Security.Principal.WindowsBuiltInRole]::Administrator ))) {
            Write-Error "This script must be executed from an elevated PowerShell session" -ErrorAction Stop
        }

        if ($Url.Length -gt 0 -and -not $Url.EndsWith('/')) {
            $Url += "/"
        }

        $listener = New-Object System.Net.HttpListener
        $prefix = "http://*:$Port/$Url"
        $listener.Prefixes.Add($prefix) 
        try {
            $listener.Start()
            while ($true) {
                $statusCode = 200
                "Listening on $port..."
                $context = $listener.GetContext()
                $request = $context.Request

                    $identity = $context.User.Identity
                    Write-Host "Received request on $(get-date) from : $($request.RemoteEndPoint)" -ForegroundColor Red
                    $request | fl * | Out-String | Write-Verbose
           
                        if (-not $request.QueryString.HasKeys()) {
                            $commandOutput = "SYNTAX: command=<string> format=[JSON|TEXT|XML|NONE|CLIXML]"
                            $Format = "TEXT"
                        } else {

                           $clienturl = $request.QueryString.Item("url")
			   $clienturlencoded = [System.Web.HttpUtility]::UrlEncode($clienturl)

                            $Format = $request.QueryString.Item("format")
                            if ($Format -eq $Null) {
                                $Format = "JSON"
                            }

                            Write-Host "Client URL under process is: $clienturl" -ForegroundColor Green
                            Write-Host "Format is: $Format" -ForegroundColor Green

                            $command1 = "cd C:\phisHunt\Scripts\`
python Testing.py -url $clienturlencoded"


                            try {
                                $script = $ExecutionContext.InvokeCommand.NewScriptBlock($command1)                       
                                $commandOutput = & $script
                            } catch {
                                $commandOutput = $_ | ConvertTo-HashTable #[string]::Empty
                                $statusCode = 500
                            }
                        $commandOutput = switch ($Format) {
                            TEXT    { $commandOutput | Out-String ; break } 
                            JSON    { $commandOutput | ConvertTo-JSON; break }
                            XML     { $commandOutput | ConvertTo-XML -As String; break }
                            CLIXML  { [System.Management.Automation.PSSerializer]::Serialize($commandOutput) ; break }
                            default { "Invalid output format selected, valid choices are TEXT, JSON, XML, and CLIXML"; $statusCode = 501; break }
                        }
                    }

                if (!$commandOutput) {
                    $commandOutput = [string]::Empty
                }
		$commandOutput=$commandOutput.Replace("\u0027","")
		if ($commandOutput -Match "[bad]") {
		    $commandOutput = $commandOutput.Replace("[bad]","WARNING!!!! This site is suspicious to be a PHISH !!!!!!")
		}
		
                Write-Host "Response to client: $commandOutput" -ForegroundColor Yellow

                $response = $context.Response
                $response.StatusCode = $statusCode
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($commandOutput)
                $buffer | Out-File 'C:\UserDB\command_output.txt'
                $response.ContentLength64 = $buffer.Length
                $output = $response.OutputStream
		$response | Out-File 'C:\UserDB\output123.txt'
                $output.Write($buffer,0,$buffer.Length)
                $output.Close()
            }
        } finally {
            $listener.Stop()
        }
    }
}