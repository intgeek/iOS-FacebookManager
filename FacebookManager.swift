//
//  APFacebookManager.swift
//  OnDemandApp
//
//  Created by Shwetabh Singh on 01/07/16.
//  Copyright © 2016 Appster. All rights reserved.
//

import Foundation
import FBSDKCoreKit
//import FBSDKShareKit
import FBSDKLoginKit
import Social

// Completion Handler returns user or error
typealias FBCompletionHandler = (userDict: [String : String]?, error: NSError?) -> Void

class APFacebookManager {
    
    private static var manager = APFacebookManager()
    //var facebookAppID: String?
    var configuration : FacebookConfiguration = FacebookConfiguration.defaultConfiguration()
    var fbCompletionHandler: FBCompletionHandler?
    
    var user : [String : String]? = [String : String]()
    
    
    // MARK: - Singleton Instance
    /**
     Initializes FacebookManager class to have a new instance of manager
     
     - parameter config: requires a FacebookConfiguration instance which is required to configure the manager
     
     - returns: an instance of FacebookManager which can be accessed via sharedManager()
     */
    class func managerWithConfiguration(config: FacebookConfiguration!) -> APFacebookManager {
        
        if config != nil {
            manager.configuration = config!
            manager.configuration.isConfigured = true
        }
        return manager
    }
    
    class func sharedManager() -> APFacebookManager {
        if isManagerConfigured() == false {
            managerWithConfiguration(FacebookConfiguration.defaultConfiguration())
        }
        return manager
    }
    
    
    // MARK: - Helpers for Manager
    private class func isManagerConfigured() -> Bool {
        return self.manager.configuration.isConfigured
    }
    
    class func resetManager() {
        self.manager.configuration.isConfigured = false
    }
    
    
    // MARK: - Token
    class func token() -> FBSDKAccessToken? {
        return FBSDKAccessToken.currentAccessToken()
    }
    
    func tokenString() -> String {
        return FBSDKAccessToken.currentAccessToken().tokenString
    }
    
    func isTokenValid() -> Bool {
        if let _ = FBSDKAccessToken.currentAccessToken() {
            return true
        } else {
            return false
        }
    }
    
    
    // MARK: Profile
    func currentProfile() -> FBSDKProfile {
        return FBSDKProfile.currentProfile()
    }
    
    func logout() {
        
        FBSDKLoginManager().logOut()
        
        // flush permissions
        configuration.permissions = []
    }
    
    private func loginWithAccountFramework() {
        let accountStore = ACAccountStore()
        let accountType = accountStore.accountTypeWithAccountTypeIdentifier(ACAccountTypeIdentifierFacebook)
        

        var options = [String: AnyObject]()
        options = [ACFacebookAppIdKey: FacebookConfiguration.fbAppId(),
                       ACFacebookPermissionsKey: [FacebookConfiguration.Permissions.PublicProfile, FacebookConfiguration.Permissions.Email],
                       ACFacebookAudienceKey: ACFacebookAudienceFriends]
        }
        accountStore.requestAccessToAccountsWithType(accountType, options: options) { (success, error) -> Void in
            
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                
                if !success {
                    self.fbCompletionHandler!(userDict : nil, error: NSError(domain: "Error", code: 201, userInfo: ["info" : error.localizedDescription]))
                    return
                }
                
                let accounts = accountStore.accountsWithAccountType(accountType) as! [ACAccount]
                
                guard let fbAccount = accounts.first else {
                    
                    self.fbCompletionHandler!(userDict : nil, error: NSError(domain: "Error", code: 201, userInfo: ["info":"There is no Facebook account configured. You can add or create a Facebook account in Settings."]))
                    return
                }
                
                var dict:NSDictionary = NSDictionary()
                dict=fbAccount.dictionaryWithValuesForKeys(["properties"])
                let properties:NSDictionary=dict["properties"] as! NSDictionary
                
                self.fetchProfileInfoAccountsFramework(fbAccount, completion: { (success, id) in
                    if success
                    {
                        properties.setValue(fbAccount.credential.oauthToken, forKey: "fb_accessToken")
                        properties.setValue(id, forKey: "id")
                        dispatch_async(dispatch_get_main_queue(), {
                            self.userParserForAccountsFramework(properties)
                        })
                    }
                })
            })
        }
    }
    
    private func loginWithFacebookSDK() {
        if self.isTokenValid() {
            self.fetchProfileInfo(nil)
        } else {
            LogManager.logDebug("\(configuration.permissions!)")
            
            FBSDKLoginManager().loginBehavior = .Native
            
            FBSDKLoginManager().logInWithReadPermissions(["public_profile" , "email"], fromViewController: nil) { (result:FBSDKLoginManagerLoginResult!, error:NSError!) -> Void in
                if error != nil {
                    // According to Facebook:
                    // Errors will rarely occur in the typical login flow because the login dialog
                    // presented by Facebook via single sign on will guide the users to resolve any errors.
                    
                    // Process error
                    FBSDKLoginManager().logOut()
                    self.fbCompletionHandler!(userDict: nil, error: error)
                    
                } else if result.isCancelled {
                    // Handle cancellations
                    FBSDKLoginManager().logOut()
                    self.fbCompletionHandler!(userDict: nil, error: error)
                    
                } else {
                    // If you ask for multiple permissions at once, you
                    // should check if specific permissions missing
                    var isPermissionsGranted = true
                    
                    // result.grantedPermissions returns an array of _NSCFString pointers
                    let grantedPermissions = (result.grantedPermissions as NSSet).allObjects.map( {"\($0)"} )
                    for permission in self.configuration.permissions {
                        if !grantedPermissions.contains(permission) {
                            isPermissionsGranted = false
                            break
                        }
                    }
                    
                    if isPermissionsGranted {
                        self.fetchProfileInfo(nil)
                        
                    } else {
                        // The user did not grant all permissions requested
                        // Discover which permissions are granted
                        // and if you can live without the declined ones
                        self.fbCompletionHandler!(userDict : nil , error : error)
                    }
                }
            }
        }
    }
    
    //
    // MARK: - Login
    //
    
    /**
     Login with facebook which returns dictionary with format {"email" : "" , "accountID" : "" , "name" : "" , "profilePicture" : "" , "fb_accessToken" : ""}
     
     - parameter handler: return with SocialCompletionHandler, either valid social user or with error information
     */
    
    func login(handler: FBCompletionHandler) {
        
        self.fbCompletionHandler = handler
        
        let isFacebookAppInstalled: Bool = UIApplication.sharedApplication().canOpenURL(NSURL(string: "fb://")!)
        
        if SLComposeViewController.isAvailableForServiceType(SLServiceTypeFacebook) && !isFacebookAppInstalled {
            loginWithAccountFramework()
        } else {
            loginWithFacebookSDK()
        }
    }
    
    //
    // MARK: - Profile Info
    //
    
    /**
     Returns user facebook profile information
     
     - parameter completion: gets callback once facebook server gives response
     */
    func fetchProfileInfo(completion: FBCompletionHandler?) {
        // See link for more fields:
        // http://stackoverflow.com/questions/32031677/facebook-graph-api-get-request-should-contain-fields-parameter-swift-faceb
        
        if(completion != nil) {
            self.fbCompletionHandler = completion
        }
        
        let request: FBSDKGraphRequest = FBSDKGraphRequest(graphPath: "me", parameters: ["fields": "id, email, name, first_name, last_name, gender, picture.width(400).height(400)"], HTTPMethod: "GET")
        request.startWithCompletionHandler { (connection, result, error) -> Void in
            
            if let error = error { // handle error
                self.logout()
                //LogManager.logError("error in getting profile info = \(error.localizedDescription)")
                self.fbCompletionHandler!(userDict: nil, error: NSError(domain: "Error", code: 201, userInfo: ["info" : error.localizedDescription]))
            } else {
                //LogManager.logDebug("success get profile info: = \(result!)")
                
                if let userInfo:NSDictionary = result as? NSDictionary {
                    
                    self.userParser(userInfo)
                    
                } else {
                    self.fbCompletionHandler!(userDict: nil, error: NSError(domain: "Error", code: 201, userInfo: ["info":"Invalid data received"]))
                }
            }
        }
    }
    
    func fetchProfileInfoAccountsFramework(fbAccount : ACAccount , completion : (success:Bool , id : String) -> Void) {
        let url = NSURL.init(string: "https://graph.facebook.com/me")
        let request = SLRequest.init(forServiceType: SLServiceTypeFacebook, requestMethod: SLRequestMethod.GET, URL: url, parameters: nil)
        request.account = fbAccount
        request.performRequestWithHandler { (data:NSData!, respomse:NSHTTPURLResponse!, error:NSError!) in
            do {
                let responseDict = try NSJSONSerialization.JSONObjectWithData(data, options: []) as! NSDictionary
                completion(success: true, id: responseDict.valueForKey("id") as! String)
                
            }catch  {
                
                completion(success: false, id: "")
                return
            }
        }
    }
    
    func userParser(userDict : NSDictionary) {
        
        self.user?["email"] = userDict["email"] as? String
        self.user?["accountID"] = userDict["id"] as? String
        self.user?["name"] = (userDict["first_name"] as? String)! + " " + (userDict["last_name"] as? String)!
        self.user?["profilePicture"] = userDict["picture"]!["data"]!!["url"] as? String
        self.user?["fb_accessToken"] = (APFacebookManager.token()?.tokenString)!
        self.fbCompletionHandler!(userDict:self.user , error : nil)
    }
    
    func userParserForAccountsFramework(userDict : NSDictionary) {
        
        self.user?["email"] = userDict["ACUIDisplayUsername"] as? String
        self.user?["accountID"] = userDict["id"] as? String//String(userDict["uid"] as! Int)
        self.user?["name"] = userDict["ACPropertyFullName"] as? String
        self.user?["profilePicture"] = "http://graph.facebook.com/\(String(userDict["uid"] as! Int))/picture?type=large"
        self.user?["fb_accessToken"] = userDict["fb_accessToken"] as? String
        self.fbCompletionHandler!(userDict:self.user , error : nil)
    }
    
    
    //
    // MARK: - Friends
    //
    
    /**
     Returns user's facebook friends who are using current application
     
     - parameter completion: gets callback once facebook server gives response
     */
    func getFriends(completion: (result: NSDictionary?, error: NSError?) -> Void) {
        
        let request: FBSDKGraphRequest = FBSDKGraphRequest(graphPath: "me/friends", parameters: ["fields": "id, email, name, first_name, last_name, gender, picture"], HTTPMethod: "GET")
        request.startWithCompletionHandler { (connection, result, error) -> Void in
            
            if let error = error { // handle error
                self.logout()
                //LogManager.logError("error in getting friends = \(error.localizedDescription)")
                completion(result: nil, error: NSError(domain: "Error", code: 201, userInfo: ["info" : error.localizedDescription]))
            } else {
                //LogManager.logDebug("success get friends: = \(result!)")
                if let friends:NSDictionary = result as? NSDictionary {
                    completion(result: friends, error: nil)
                } else {
                    completion(result: nil, error: NSError(domain: "Error", code: 201, userInfo: ["info":"Invalid data received"]))
                }
            }
        }
    }
    
    //
    // MARK: - Share link content
    //
    
    /**
     Post a Link with image having a caption, description and name
     * Link with image is posted on the me/feed graph path
     * link : NSURL - link to be shared with post
     * picture : NSURL - picture to be shred with post
     * name : NSString - Name for post( appears like a title)
     * description : NSString - Description for post ( appears like a subtitle)
     * caption : NSString - caption for image (apeears at bottom)
     * competion : gets callback once facebook server gives response
     */
    func shareLinkContent(link: NSURL, picture: NSURL, name: String, description: NSString, caption: NSString, completion: (result: NSDictionary?, error: NSError?) -> Void) {
        
        let  params =  ["" : "null",
                        "link" : link.absoluteString,
                        "picture" : picture.absoluteString,
                        "name" : name,
                        "description": description,
                        "caption": caption]
        
        let request = FBSDKGraphRequest(graphPath:"me/feed", parameters:params, HTTPMethod:"POST")
        
        request.startWithCompletionHandler{(connection,result,error)->Void in
            if let error = error {
                //LogManager.logError("error in posting link with image = \(error)")
                completion(result: nil, error: NSError(domain: "Error", code: 201, userInfo: ["info" : error.localizedDescription]))
            } else {
                //LogManager.logDebug("success in posting link with image: = \(result!)")
                if let id:NSDictionary = result as? NSDictionary {
                    completion(result: id, error: nil)
                } else {
                    completion(result: nil, error: NSError(domain: "Error", code: 201, userInfo: ["info":"Invalid data received"]))
                }
            }
        }
    }
    
}


// MARK: - Facebook Configutaion Class

class FacebookConfiguration {
    
    static var fbConfiguration: FacebookConfiguration?
    
    var isConfigured: Bool! = false
    var permissions: [String]!
    var facebookAppID : String! = "Your_FB_APPID"
    
    // MARK: - Permissions
    struct Permissions {
        static let PublicProfile = "public_profile"
        static let Email = "email"
        static let UserFriends = "user_friends"
        static let UserAboutMe = "user_about_me"
        static let UserBirthday = "user_birthday"
        static let UserHometown = "user_hometown"
        static let UserLikes = "user_likes"
        static let UserInterests = "user_interests"
        static let UserPhotos = "user_photos"
        static let FriendsPhotos = "friends_photos"
        static let FriendsHometown = "friends_hometown"
        static let FriendsLocation = "friends_location"
        static let FriendsEducationHistory = "friends_education_history"
    }
    
    init(scope: [String]) {
        permissions = scope
    }
    
    class func customConfiguration(customPermissions : [String]) -> FacebookConfiguration {
        
        if fbConfiguration == nil {
            fbConfiguration = FacebookConfiguration(scope: customPermissions)
        }
        return fbConfiguration!
    }
    
    class func defaultConfiguration() -> FacebookConfiguration {
        
        if fbConfiguration == nil {
            fbConfiguration = FacebookConfiguration(scope: defaultPermissions())
        }
        
        // Optionally add to ensure your credentials are valid:
        FBSDKLoginManager.renewSystemCredentials { (result: ACAccountCredentialRenewResult, error: NSError!) -> Void in
            if let _ = error {
                //LogManager.logError(error.localizedDescription)
            }
        }
        
        return fbConfiguration!
    }
    
    // MARK: - Helpers
    private class func fbAppId() -> String! {
        return FacebookConfiguration.fbConfiguration?.facebookAppID
    }
    
    class func defaultPermissions() -> [String] {
        return [Permissions.PublicProfile, Permissions.Email]
    }   
}
