//
//  StripeRequest.swift
//  Stripe
//
//  Created by Anthony Castelli on 4/13/17.
//
//

import Foundation
import NIO
import NIOFoundationCompat
import NIOHTTP1
import AsyncHTTPClient

internal let APIBase = "https://api.stripe.com/"
internal let FilesAPIBase = "https://files.stripe.com/"
internal let APIVersion = "v1/"

public protocol StripeAPIHandler {
    func send<SM: StripeModel>(method: HTTPMethod,
                               path: String,
                               query: String,
                               body: HTTPClient.Body,
                               headers: HTTPHeaders) -> EventLoopFuture<SM>
}

extension StripeAPIHandler {
    func send<SM: StripeModel>(method: HTTPMethod,
                               path: String,
                               query: String = "",
                               body: HTTPClient.Body = .string(""),
                               headers: HTTPHeaders = [:]) -> EventLoopFuture<SM> {
        return send(method: method,
                    path: path,
                    query: query,
                    body: body,
                    headers: headers)
    }
}

struct StripeDefaultAPIHandler: StripeAPIHandler {
    private let httpClient: HTTPClient
    private let apiKey: String
    private let decoder = JSONDecoder()
    var eventLoop: EventLoop

    init(httpClient: HTTPClient, eventLoop: EventLoop, apiKey: String) {
        self.httpClient = httpClient
        self.eventLoop = eventLoop
        self.apiKey = apiKey
        decoder.dateDecodingStrategy = .secondsSince1970
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }
    
    public func send<SM: StripeModel>(method: HTTPMethod,
                                      path: String,
                                      query: String = "",
                                      body: HTTPClient.Body = .string(""),
                                      headers: HTTPHeaders = [:]) -> EventLoopFuture<SM> {
        
        var _headers: HTTPHeaders = ["Stripe-Version": "2019-12-03",
                                     "Authorization": "Bearer \(apiKey)",
                                     "Content-Type": "application/x-www-form-urlencoded"]
        headers.forEach { _headers.replaceOrAdd(name: $0.name, value: $0.value) }
        
        do {
            let request = try HTTPClient.Request(url: "\(path)?\(query)", method: method, headers: _headers, body: body)
            
            return httpClient.execute(request: request, eventLoop: .delegate(on: self.eventLoop)).flatMap { response in
                guard var byteBuffer = response.body else {
                    fatalError("Response body from Stripe is missing! This should never happen.")
                }
                let responseData = byteBuffer.readData(length: byteBuffer.readableBytes)!
                
                do {
                    guard response.status == .ok else {
                        return self.eventLoop.makeFailedFuture(try self.decoder.decode(StripeError.self, from: responseData))
                    }
                    return self.eventLoop.makeSucceededFuture(try self.decoder.decode(SM.self, from: responseData))

                } catch {
                    return self.eventLoop.makeFailedFuture(error)
                }
            }
        } catch {
            return self.eventLoop.makeFailedFuture(error)
        }
    }
}