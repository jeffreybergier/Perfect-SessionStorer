//
//  SessionStorage.swift
//  SwiftRoom
//
//  Created by Jeffrey Bergier on 10/24/16.
//
//

import CryptoSwift
import PerfectHTTP
import PerfectThread
import Foundation

// MARK: Protocols

public protocol SessionStorerDelegateProtocol: class {
    associatedtype K
    func willStore(value: K?, forKey key: String, withToken token: String, on response: HTTPResponse?, storer: SessionStorer<K>) -> K?
    func shouldReturn(value: K?, forKey key: String, withToken token: String, for request: HTTPRequest, storer: SessionStorer<K>) -> Bool
    func willReturn(value: K?, forKey key: String, withToken token: String, for request: HTTPRequest, storer: SessionStorer<K>) -> K?
    func didReturn(value: K?, forKey key: String, withToken token: String, for request: HTTPRequest, storer: SessionStorer<K>)
    func deleted(expired values: [String : K], withToken token: String, storer: SessionStorer<K>)
}

public protocol SessionStorerDataSourceProtocol: class {
    associatedtype K
    subscript(storer: SessionStorer<K>, key: String) -> Expire<[String : K]>? { get set }
    func expiredItems(storer: SessionStorer<K>) ->[(key: String,  value: Expire<[String : K]>)]
}

// MARK: Abstract Super Classes - Hopefully we will get Generic Protocols and we can get rid of these

open class SessionStorerDelegate<E>: SessionStorerDelegateProtocol {
    public typealias K = E
    public init() {}
    open func willStore(value: E?, forKey key: String, withToken token: String, on response: HTTPResponse?, storer: SessionStorer<E>) -> E? { return .none }
    open func shouldReturn(value: E?, forKey key: String, withToken token: String, for request: HTTPRequest, storer: SessionStorer<E>) -> Bool { return true }
    open func willReturn(value: E?, forKey key: String, withToken token: String, for request: HTTPRequest, storer: SessionStorer<E>) -> E? { return .none }
    open func didReturn(value: E?, forKey key: String, withToken token: String, for request: HTTPRequest, storer: SessionStorer<E>) { }
    open func deleted(expired values: [String : E], withToken token: String, storer: SessionStorer<E>) {}
}

open class SessionStorerDataSource<E>: SessionStorerDataSourceProtocol {
    public typealias K = E
    public init() {}
    open subscript(storer: SessionStorer<K>, key: String) -> Expire<[String : K]>? {
        get { fatalError("SessionStorerDataSource is an abstract superclass that does not save any data. You need to subclass and create your own data source.") }
        set { fatalError("SessionStorerDataSource is an abstract superclass that does not save any data. You need to subclass and create your own data source.") }
    }
    open func expiredItems(storer: SessionStorer<K>) -> [(key: String,  value: Expire<[String : E]>)] { return [] }
}

// MARK: Main Session Storer Class

open class SessionStorer<T> {
    
    // MARK: Constant properties
    
    public let sessionCookieName: String
    public let sessionExpiration: TimeInterval
    public private(set) var filter: SessionStorerFilter!
    
    // MARK:  Public interface
    public weak var dataSource: SessionStorerDataSource<T>?
    public weak var delegate: SessionStorerDelegate<T>?

    public init(sessionCookieName: String = "perfect-session", sessionExpiration: TimeInterval = 365*24*60*60, delegate: SessionStorerDelegate<T>? = .none, dataSource: SessionStorerDataSource<T>? = .none) {
        // configure constants
        self.sessionCookieName = sessionCookieName
        self.sessionExpiration = sessionExpiration
        
        // configure the delegate and data source
        self.delegate = delegate
        self.dataSource = dataSource
        
        // configure Filter and prepare to add cookies to all incoming packets
        self.filter = SessionStorerFilter()
        self.filter.requestCallback = { [weak self] request, response in
            guard let guardedSelf = self, guardedSelf.checkToken(for: request) == .none else { return }
            guardedSelf.generateSessionTokenAndCookie(for: request, andFor: response)
        }
        
        // start the timer for deleting old objects
        Threading.getQueue(name: "SessionStorage::ValueExpirationCheckingThread", type: .concurrent).dispatch {
            self.removeExpiredValues()
        }
    }
    
    private func generateSessionTokenAndCookie(for request: HTTPRequest, andFor response: HTTPResponse) {
        let newToken = AES.randomIV(16).toBase64()!.encodingCookieCompatibility!
        let doubleToken = newToken.encodingCookieCompatibility!
        let cookie = PerfectHTTP.HTTPCookie.cookies(with: [self.sessionCookieName : newToken], expiresIn: self.sessionExpiration).first!
        
        response.addCookie(cookie)
        request.setHeader(HTTPRequestHeader.Name.cookie, value: cookie.name + "=" + doubleToken) // not sure why I have to cookie encode this twice
    }
    
    public subscript(request: HTTPRequest, key: String) -> T? {
        get {
            return self.value(forKey: key, for: request)
        }
        set {
            self.set(value: newValue, forKey: key, for: request)
        }
    }
    
    public subscript(request: HTTPRequest, response: HTTPResponse?, key: String) -> T? {
        get {
            return self.value(forKey: key, for: request)
        }
        set {
            self.set(value: newValue, forKey: key, for: request, response: response)
        }
    }
    
    public func set(value: T?, forKey key: String, for request: HTTPRequest, response: HTTPResponse? = nil) {
        // get the token
        let token = self.token(for: request)
        
        // check with the delegate to see if it wants to change what is being saved
        let value = self.delegate?.willStore(value: value, forKey: key, withToken: token, on: response, storer: self) ?? value
        
        // get the container
        let container = self.existingOrNewDictionaryContainer(for: token)
        var dictionary = container.value
        
        // set the information and reset the expiration of the information
        dictionary[key] = value
        self.dataSource?[self, token] = Expire(value: dictionary, expiresIn: self.sessionExpiration)
    }
    
    public func value(forKey key: String, for request: HTTPRequest) -> T? {
        // get the token
        let token = self.token(for: request)
        
        // get the existing value
        let container = self.existingOrNewDictionaryContainer(for: token)
        let value = container.value[key]
        
        // check if we should return the value from the delegate
        guard self.delegate?.shouldReturn(value: value, forKey: key, withToken: token, for: request, storer: self) ?? true else { return .none }
        
        // check with delegate to see if we already have a value to return
        let delegateValue = self.delegate?.willReturn(value: value, forKey: key, withToken: token, for: request, storer: self)
        
        // figure out which value we're going to return
        let returnedValue = delegateValue ?? value
        
        // let the delegate know that we did return the values after we exit the scope
        defer { self.delegate?.didReturn(value: returnedValue, forKey: key, withToken: token, for: request, storer: self) }
        
        // return the data
        return returnedValue
    }
    
    // MARK: private timer to delete expired values
    
    private func removeExpiredValues() {
        // Find expired containers
        let expiredContainers = self.dataSource?.expiredItems(storer: self)
        
        // delete expired containers
        expiredContainers?.forEach() { (token, container) in
            self.dataSource?[self, token] = .none
            self.delegate?.deleted(expired: container.value, withToken: token, storer: self)
        }
        
        // sleep for 60 seconds and then repeat
        Threading.sleep(seconds: 60)
        self.removeExpiredValues()
    }
    
    // MARK: private helper methods
    
    private func existingOrNewDictionaryContainer(for token: String) -> Expire<[String : T]> {
        return self.dataSource?[self, token] ?? Expire(value: [String : T](), expiresIn: self.sessionExpiration)
    }
    
    private func checkToken(for request: HTTPRequest) -> String? {
        return request.cookies.filter({ $0.0 == self.sessionCookieName }).last?.1.decodingCookieCompatibility
    }
    
    public func token(for request: HTTPRequest) -> String {
        guard let token = self.checkToken(for: request)
            else { fatalError("No token present in request. You probably need to install the request filter for this storer.") }
        return token
    }
}

// MARK: Helper Types

public class SessionStorerFilter: HTTPRequestFilter {
    fileprivate var requestCallback: ((HTTPRequest, HTTPResponse) -> Void)!
    public func filter(request: HTTPRequest, response: HTTPResponse, callback: (HTTPRequestFilterResult) -> ()) {
        self.requestCallback(request, response)
        callback(.`continue`(request, response))
    }
}


public struct Expire<V> {
    
    var value: V
    var startDate: Date
    var count: TimeInterval
    
    var isExpired: Bool {
        let now = Date()
        let startDatePlusInterval = self.startDate + self.count
        return now > startDatePlusInterval
    }
    
    init(value: V, expiresIn: TimeInterval) {
        self.startDate = Date()
        self.count = expiresIn
        self.value = value
    }
}
