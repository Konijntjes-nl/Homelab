# Send-EmailAlert.ps1
param (
    [string]$Subject = "CyberArk Alert",
    [string]$Body = "A CyberArk monitoring threshold was triggered.",
    [string]$To = "admin@company.com"
)

Send-MailMessage -To $To -From "cyberark-monitor@company.com" `
    -Subject $Subject -Body $Body -SmtpServer "smtp.company.com"
