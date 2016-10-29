//
//  OffTheShelf.swift
//  SwiftRoom
//
//  Created by Jeffrey Bergier on 10/28/16.
//
//

import PerfectHTTP

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
    public subscript(storer: SessionStorer<K>, key: String) -> Expire<[String : K]>? {
        get {
            fatalError("SessionStorerDataSource is an abstract superclass that does not save any data. You need to subclass and create your own data source.")
        }
        set {
            fatalError("SessionStorerDataSource is an abstract superclass that does not save any data. You need to subclass and create your own data source.")
        }
    }
    public func expiredItems(storer: SessionStorer<K>) -> [(key: String,  value: Expire<[String : E]>)] {
        return []
    }
}

open class SessionStorerInMemoryDataSource<E>: SessionStorerDataSource<E> {
    private var storage = [String : Expire<[String : E]>]()
    public override subscript(storer: SessionStorer<E>, key: String) -> Expire<[String : E]>? {
        get {
            return self.storage[key]
        }
        set {
            self.storage[key] = newValue
        }
    }
    public override func expiredItems(storer: SessionStorer<E>) -> [(key: String,  value: Expire<[String : E]>)] {
        return self.storage.filter({ $0.value.isExpired })
    }
}
