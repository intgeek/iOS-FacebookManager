# iOS-FacebookManager
Swift facebook manager for iOS applications.

Just import facebook manager class to your project and you will get result dictionary in following format :
{
"email" : "" , 
"accountID" : "" , 
"name" : "" , 
"profilePicture" : ""
}

Call the following method from your view controller.
  FacebookManager.sharedManager().login { (userDict, error) in
            if(error != nil)
            {
                print(error)
            }
            else {
                print(userDict)
            }

Call the following method before login if you want to tweek the permissions.

  FacebookManager.managerWithConfiguration(FacebookConfiguration.customConfiguration([FacebookConfiguration.Permissions.PublicProfile, FacebookConfiguration.Permissions.Email]))

Initial setup of info.plist and appdelegate methods is same as provided by facebook developer documentation.
