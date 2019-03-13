# bottroubleshooter
This powershell script can help troubleshoot Bot Service Setup, Configuration and Connectivity issues with webchat.
You are expected to pass the the subscriptionID and the Name of the BotService. The botservice name can be retrieved from Azure Portal under "Bot Services", the name can be either Web App Bot or Bot Channel Registration"

Here are the things this troubleshooter can help you with:
1. Check if you have neccesary permissions to create a Bot service, will tell you the details of the claims you are missing	
2. Detects if the endpoint is hosted as Azure Web App and if so it will validate AppID and Password between the customer BOT endpoint and the bot service.
3.	Validate BOT endpoints availability and check for different status 
 <br> a.	DNS and Name resolution
  <br>b.	Validate REST API endpoint
  <br>c.	Status of endpoint (example if the Web App is in stopped state)
  <br>d.	Endpoint failing with exception
  <br>e.	If the BOT endpoint uses custom host name, the script will still detect if its hosted on Web App and then performs all of the above checks. 
4. If you are using an on-premise solution it will provide you details of what ports you need to open.
5. If the webchat fails due to incorrect appId, the script detects if the appID is registered properly in Azure AD and recommends the right steps to register the AppID.

How to Use :

You will need the subscriptionID and the Name of the BotService. The botservice name can retrieved from Azure Portal under "Bot Services", the name can be either Web App Bot or Bot Channel Registration".

1.	Download the powershell script “BotTroubleshooter.ps1” from Github.
2.	Open Powershell console and run the below script as below 
           .\BotTroubleshooter.ps1 -subscriptionId <Subscription-ID> 

Once you run the above command you will be provided two options:
1. Type 1 if you are have issues creating BotService 
2. Type 2 if you are have issues with Webchat connectivity 

For option 1, no further inputs are needed.
For option 2, you will need to provide the bot service name

** when you run the script you may get powershell error 'BotTroubleshooter.ps1 cannot be loaded and not digitally signed'. Please run 'Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass' **
