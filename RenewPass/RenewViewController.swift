//
//  RenewViewController.swift
//  RenewPass
//
//  Created by Kino Roy on 2017-01-31.
//  Copyright © 2017 Kino Roy. All rights reserved.
//

import UIKit
import CoreData
import WebKit
import os.log
import Crashlytics

class RenewViewController: UIViewController, CAAnimationDelegate {
    
    // MARK: - Proporties

    var renewService:RenewService!
    private var reachability:Reachability = Reachability()!
    @IBOutlet weak var reloadButton: UIButton!
    @IBOutlet weak var statusLabel: UILabel!
    var shouldContinueReloadAnimation:Bool = false

    // MARK: - Life Cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        self.statusLabel.adjustsFontSizeToFitWidth = true
        statusLabel.text = "Connecting to Translink. Just a moment."
        
        NotificationCenter.default.addObserver(forName: Notification.Name("webViewDidFinishLoad"), object: nil, queue: nil, using: webViewDidFinishLoad)
        NotificationCenter.default.addObserver(forName: Notification.Name("webViewDidFailLoadWithError"), object: nil, queue: nil, using: webViewDidFailLoadWithError)
        NotificationCenter.default.addObserver(forName: Notification.Name("statusLabelDidChange"), object: nil, queue: nil, using: statusLabelDidChange)
        // Reachability
        NotificationCenter.default.addObserver(self, selector: #selector(self.reachabilityChanged), name: ReachabilityChangedNotification, object: reachability)
        do {
            try reachability.startNotifier()
        } catch {
            os_log("Unable to start reachability", log: .default, type: .debug)
        }
        
        self.reloadButton.isEnabled = false
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        // Reset the reload button image
        self.reloadButton.setImage(#imageLiteral(resourceName: "requestButton"), for: .normal)
        // Checks if there is login data stored. If not, asks the user for login data by showing the login screen.
        if needToShowLoginScreen() {
            showLoginScreen()
        } else {
            // If the user has not been prompted to enable notifications, ask them now.
            if !UserDefaults.standard.bool(forKey: "hasAskedUserForNotifAuth") {
                Notifications.requestNotificationAuthorization(viewControllerToPresent: self)
            }
            
            //RenewService Object
            if !RenewService.didStartFetchFromBackground {
                renewService = RenewService.getInstance()
            }
            
            if !RenewService.didStartFetchFromBackground {
                reloadButton.isEnabled = false
                //webview = WebView(frame: self.view.frame)
                statusLabel.text = "Connecting to Translink. Just a moment."
                
                let url = URL(string: "https://upassbc.translink.ca")
                let urlRequest = URLRequest(url: url!)
                renewService.webview.loadRequest(urlRequest)
            }
        }
    }

    // MARK: - Navigation

    /// Displays the login screen
    func showLoginScreen() {
        
        DispatchQueue.main.async {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let signInViewController = storyboard.instantiateViewController(withIdentifier: "schoolCollectionNavigationController")
            
            self.present(signInViewController, animated: true) {
                
            }
        }
        
    }
    
    /// Determines if the login screen needs to be shown
    ///     Returns: A boolean describing whether to show the login screen or not
    func needToShowLoginScreen() -> Bool {
        
        // If the account can not be loaded or doesn't exist, we have to show the login screen
        guard (AccountManager.loadAccount() as Account?) != nil else {
            return true
        }
        
        return false
    }
    
    // MARK: - Actions
    
    @IBAction func renewButtonTouchUpInside(_ sender: Any) {
        // Reset the reload button image
        self.reloadButton.setImage(#imageLiteral(resourceName: "requestButton"), for: .normal)
        renewService.numUpass = nil
        reloadButton.isEnabled = false
        shouldContinueReloadAnimation = true
        reloadButton.rotate360Degrees(completionDelegate: self)
        
        statusLabel.text = "Selecting School"
        
        renewService.fetch() { (error) in
            self.shouldContinueReloadAnimation = false
            
            let url = URL(string: "https://upassbc.translink.ca")
            let urlRequest = URLRequest(url: url!)
            self.renewService.webview.loadRequest(urlRequest)
            
            if error != nil {
                if error == RenewPassError.alreadyHasLatestUPassError {
                    os_log("Already has the latest UPass", log: .default, type: .debug)
                    self.reloadButton.setImage(#imageLiteral(resourceName: "Checkmark"), for: .normal)
                } else {
                    Answers.logCustomEvent(withName: "RenewPassError", customAttributes: ["Error":"\(error!.title)","School":self.renewService.school.shortName])
                    self.reloadButton.setImage(#imageLiteral(resourceName: "Error"), for: .normal)
                }
            } else {
                self.statusLabel.text = "Sweet! You've snagged the latest UPass."
                self.reloadButton.setImage(#imageLiteral(resourceName: "Checkmark"), for: .normal)
            }
            self.renewService.webview.removeFromSuperview()
        }
        
        
    }
    
    
    // MARK: - Webview
    func webViewDidFinishLoad(notification:Notification) {
        //let webView = notification.object as! UIWebView
        guard let currentURL = renewService.webview.request?.url?.absoluteString else {
            fatalError("Webview did not load a URL")
        }
        
        do {
            if currentURL == "https://upassbc.translink.ca/" {
                reloadButton.isEnabled = true
                if statusLabel.text == "Connecting to Translink. Just a moment." || statusLabel.text == "Couldn't connect to UPassBC, check your connection." {
                    statusLabel.text = "Click away!"
                }
                
                if RenewService.didStartFetchFromBackground {
                    renewService.selectSchool()
                }
            } else if currentURL.contains(renewService.school.authPageURLIdentifier) { // School authentication screen
                try renewService.authenticate(school: getSchoolID(school: renewService.school.school))
            } else if currentURL.contains("fs") { // post-auth Upass site
                if renewService.numUpass == nil {
                    try renewService.checkUpass()
                } else {
                    try renewService.verifyRenew()
                }
                
            }
        } catch let error as RenewPassError {
            statusLabel.text = error.title
            renewService.completionHandlers[0](error)
        } catch {
            statusLabel.text = "Unknown Error"
            renewService.completionHandlers[0](RenewPassError.unknownError)
        }
        
    }
    
    func webViewDidFailLoadWithError(notification:Notification) {
        if renewService.completionHandlers.count > 0 {
            renewService.completionHandlers[0](RenewPassError.webViewFailedError)
        } else {
            statusLabel.text = "Couldn't connect to UPassBC, check your connection."
        }
    }
    
    // status label
    func statusLabelDidChange(notification:Notification) {
        statusLabel.text = renewService.statusLabel
    }
    
    // MARK: - Status Bar
    override var prefersStatusBarHidden: Bool {
        #if DEBUG
            return true
        #else
            return false
        #endif
    }
    
    // MARK: - CAAnimation
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        if shouldContinueReloadAnimation {
            self.reloadButton.rotate360Degrees(completionDelegate: self)
        }
    }
    
    // MARK: - Reachability 
    /// Called when the ReachabilityChangedNotificiation is posted. Enables or disables the app based on the users internet connection
    /// - Parameters:
    ///     - notification: the notification object that the function was called for
    @objc func reachabilityChanged(notification:Notification) {
        
        // Get the reachability object
        let reachability = notification.object as! Reachability
        
        // Determine if the network is reachable
        if reachability.isReachable && renewService != nil {
            // If the renew service is not yet active, don't do anything
            guard renewService != nil else {
                return
            }
          DispatchQueue.main.async {
            // Re-attempt connection to Translink
            self.statusLabel.text = "Connecting to Translink. Just a moment."
            let url = URL(string: "https://upassbc.translink.ca")
            let urlRequest = URLRequest(url: url!)
            self.renewService.webview.loadRequest(urlRequest)
          }
        } else { // No connection
          DispatchQueue.main.async {
            // Disable the app
            self.statusLabel.text = "Couldn't connect to UPassBC, check your connection."
            self.reloadButton.isEnabled = false
          }
        }
    }
}
