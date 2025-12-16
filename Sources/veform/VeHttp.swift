//
//  TewyHttp.swift
//  conversation-app
//
//  Created by Eric McElyea on 10/15/25.
//

import Foundation
import Network


let url = "https://b8bd01f5b159.ngrok-free.app"
class VeHttp: NSObject {
    let basepath:String =  url


    func getForm(id: String) async throws -> Form? {
        let url = URL(string: basepath + "/form/\(id)")!
        print("Making thtp request to url: \(url)")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
          (200...299).contains(httpResponse.statusCode) else {
            print("Invalid response from server")
            return nil
        }
        let decoder = JSONDecoder()
        let form = try decoder.decode(Form.self, from: data)
        return form
    }
}
