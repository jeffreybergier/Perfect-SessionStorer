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

public class SessionStorerFilter: HTTPRequestFilter {
    
    fileprivate var requestCallback: ((HTTPRequest, HTTPResponse) -> Void)!
    
    public func filter(request: HTTPRequest, response: HTTPResponse, callback: (HTTPRequestFilterResult) -> ()) {
        self.requestCallback(request, response)
        callback(.`continue`(request, response))
    }
}

public protocol SessionDataStorerDelegate: class {
    
    associatedtype K
    
    func willStore(value: K?, forKey key: String, withToken token: String, on response: HTTPResponse?, storer: SessionDataStorer<K, Self>) -> K?
    func shouldReturn(value: K?, forKey key: String, withToken token: String, for request: HTTPRequest, storer: SessionDataStorer<K, Self>) -> Bool
    func willReturn(value: K?, forKey key: String, withToken token: String, for request: HTTPRequest, storer: SessionDataStorer<K, Self>) -> K?
    func didReturn(value: K?, forKey key: String, withToken token: String, for request: HTTPRequest, storer: SessionDataStorer<K, Self>)
    func deleted(expired values: [String : K], withToken token: String, storer: SessionDataStorer<K, Self>)
}

public final class SessionDataStorerNILDelegate<E>: SessionDataStorerDelegate {
    public typealias K = E
    public func willStore(value: K?, forKey key: String, withToken token: String, on response: HTTPResponse?, storer: SessionDataStorer<K, SessionDataStorerNILDelegate>) -> K? { return .none }
    public func shouldReturn(value: K?, forKey key: String, withToken token: String, for request: HTTPRequest, storer: SessionDataStorer<K, SessionDataStorerNILDelegate>) -> Bool { return true }
    public func willReturn(value: K?, forKey key: String, withToken token: String, for request: HTTPRequest, storer: SessionDataStorer<K, SessionDataStorerNILDelegate>) -> K? { return .none }
    public func didReturn(value: K?, forKey key: String, withToken token: String, for request: HTTPRequest, storer: SessionDataStorer<K, SessionDataStorerNILDelegate>) { }
    public func deleted(expired values: [String : K], withToken token: String, storer: SessionDataStorer<K, SessionDataStorerNILDelegate>) {}
}

open class SessionDataStorer<T, D: SessionDataStorerDelegate> where D.K == T {
    
    // MARK: Constant properties
    
    public let sessionCookieName: String
    public let sessionExpiration: TimeInterval
    public private(set) var filter: SessionStorerFilter!
    
    // MARK: Private storage, do not touch
    
    private var storage: [String : Expire<[String : T]>] = [:]
    private var activeConnections = [(HTTPRequest, HTTPResponse)]()
    
    // MARK:  Public interface
    
    public weak var delegate: D?

    public init(sessionCookieName: String = "perfect-session", sessionExpiration: TimeInterval = 365*24*60*60) {
        self.sessionCookieName = sessionCookieName
        self.sessionExpiration = sessionExpiration
        
        self.filter = SessionStorerFilter()
        self.filter.requestCallback = { [weak self] request, response in
            guard let guardedSelf = self, guardedSelf.existingToken(for: request) == .none else { return }
            guardedSelf.generateSessionTokenAndCookie(for: request, andFor: response)
        }
        
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
        let token = self.existingToken(for: request)!
        
        // check with the delegate to see if it wants to change what is being saved
        let value = self.delegate?.willStore(value: value, forKey: key, withToken: token, on: response, storer: self) ?? value
        
        // get the container
        let container = self.existingOrNewDictionaryContainer(for: token)
        var dictionary = container.value
        
        // set the information and reset the expiration of the information
        dictionary[key] = value
        self.storage[token] = Expire(value: dictionary, expiresIn: self.sessionExpiration)
    }
    
    public func value(forKey key: String, for request: HTTPRequest) -> T? {
        // get the token
        let token = self.existingToken(for: request)!
        
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
        let expiredContainers = self.storage.filter({ $0.value.isExpired })
        
        // delete expired containers
        expiredContainers.forEach() { (token, container) in
            self.storage.removeValue(forKey: token)
            self.delegate?.deleted(expired: container.value, withToken: token, storer: self)
        }
        
        // sleep for 60 seconds and then repeat
        Threading.sleep(seconds: 60)
        self.removeExpiredValues()
    }
    
    // MARK: private helper methods
    
    private func existingOrNewDictionaryContainer(for token: String) -> Expire<[String : T]> {
        return self.storage[token] ?? Expire(value: [String : T](), expiresIn: self.sessionExpiration)
    }
    
    private func existingToken(for request: HTTPRequest) -> String? {
        return request.cookies.filter({ $0.0 == self.sessionCookieName }).last?.1.decodingCookieCompatibility
    }
}

internal struct Expire<V> {
    
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

public extension PerfectHTTP.HTTPCookie {
    static func cookies(with values: [String : String], expiresIn: TimeInterval) -> [PerfectHTTP.HTTPCookie] {
        let cookies = values.map() { (key, value) -> PerfectHTTP.HTTPCookie in
            let cookie = PerfectHTTP.HTTPCookie(
                name: key,
                value: value,
                domain: nil,
                expires: .relativeSeconds(Int(expiresIn)),
                path: "/",
                secure: false,
                httpOnly: true
            )
            return cookie
        }
        return cookies
    }
}

public extension String {
    
    var encodingCookieCompatibility: String? {
        return self.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
    }
    
    var decodingCookieCompatibility: String? {
        return self.removingPercentEncoding
    }
    
}
