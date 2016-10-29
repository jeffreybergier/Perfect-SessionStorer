//
//  Extensions.swift
//  SwiftRoom
//
//  Created by Jeffrey Bergier on 10/28/16.
//
//

import PerfectHTTP
import Foundation

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
