//
//  VimeoSessionManager+Upload.swift
//  VimeoUpload
//
//  Created by Alfred Hanssen on 10/21/15.
//  Copyright © 2015 Vimeo. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation
import VimeoNetworking

enum UploadTaskDescription: String
{
    case Me = "Me"
    case MyVideos = "MyVideos"
    case CreateVideo = "CreateVideo"
    case UploadVideo = "UploadVideo"
    case ActivateVideo = "ActivateVideo"
    case VideoSettings = "VideoSettings"
    case DeleteVideo = "DeleteVideo"
    case Video = "Video"
    case CreateThumbnail = "CreateThumbnail"
    case UploadThumbnail = "UploadThumbnail"
    case ActivateThumbnail = "ActivateThumbnail"
}

extension VimeoSessionManager
{
    public func meDataTask(completionHandler: UserCompletionHandler) throws -> URLSessionDataTask
    {
        let request = try (self.requestSerializer as! VimeoRequestSerializer).meRequest()

        let task = self.dataTaskWithRequest(request, completionHandler: { [weak self] (response, responseObject, error) -> Void in

            // Do model parsing on a background thread
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), { [weak self] () -> Void in
                
                guard let strongSelf = self else
                {
                    return
                }

                do
                {
                    let user = try (strongSelf.responseSerializer as! VimeoResponseSerializer).processMeResponse(response, responseObject: responseObject, error: error)
                    completionHandler(user: user, error: nil)
                }
                catch let error as NSError
                {
                    completionHandler(user: nil, error: error)
                }
            })
        })
        
        task.taskDescription = UploadTaskDescription.Me.rawValue
        
        return task
    }

    public func myVideosDataTask(completionHandler: VideosCompletionHandler) throws -> URLSessionDataTask
    {
        let request = try (self.requestSerializer as! VimeoRequestSerializer).myVideosRequest()
        
        let task = self.dataTaskWithRequest(request, completionHandler: { [weak self] (response, responseObject, error) -> Void in
            
            // Do model parsing on a background thread
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), { [weak self] () -> Void in
                
                guard let strongSelf = self else
                {
                    return
                }
                
                do
                {
                    let videos = try (strongSelf.responseSerializer as! VimeoResponseSerializer).processMyVideosResponse(response, responseObject: responseObject, error: error)
                    completionHandler(videos: videos, error: nil)
                }
                catch let error as NSError
                {
                    completionHandler(videos: nil, error: error)
                }
            })
        })
        
        task.taskDescription = UploadTaskDescription.MyVideos.rawValue
        
        return task
    }

    public func createVideoDownloadTask(url: NSURL) throws -> URLSessionDownloadTask
    {
        let request = try (self.requestSerializer as! VimeoRequestSerializer).createVideoRequestWithUrl(url)

        let task = self.downloadTaskWithRequest(request, progress: nil, destination: nil, completionHandler: nil)
        
        task.taskDescription = UploadTaskDescription.CreateVideo.rawValue
        
        return task
    }
    
    func uploadVideoTask(source: NSURL, destination: String, completionHandler: ErrorBlock?) throws -> URLSessionUploadTask
    {
        let request = try (self.requestSerializer as! VimeoRequestSerializer).uploadVideoRequestWithSource(source, destination: destination)
        
        let task = self.uploadTaskWithRequest(request, fromFile: source, progress: nil, completionHandler: { [weak self] (response, responseObject, error) -> Void in

            guard let strongSelf = self, let completionHandler = completionHandler else
            {
                return
            }
            
            do
            {
                try (strongSelf.responseSerializer as! VimeoResponseSerializer).processUploadVideoResponse(response, responseObject: responseObject, error: error)
                completionHandler(error: nil)
            }
            catch let error as NSError
            {
                completionHandler(error: error)
            }

        })
        
        task.taskDescription = UploadTaskDescription.UploadVideo.rawValue
        
        return task
    }
    
    // For use with background sessions, use session delegate methods for destination and completion
    func activateVideoDownloadTask(uri activationUri: String) throws -> URLSessionDownloadTask
    {
        let request = try (self.requestSerializer as! VimeoRequestSerializer).activateVideoRequestWithUri(activationUri)
        
        let task = self.downloadTaskWithRequest(request, progress: nil, destination: nil, completionHandler: nil)
        
        task.taskDescription = UploadTaskDescription.ActivateVideo.rawValue
        
        return task
    }    

    // For use with background sessions, use session delegate methods for destination and completion
    func videoSettingsDownloadTask(videoUri: String, videoSettings: VideoSettings) throws -> URLSessionDownloadTask
    {
        let request = try (self.requestSerializer as! VimeoRequestSerializer).videoSettingsRequestWithUri(videoUri, videoSettings: videoSettings)
        
        let task = self.downloadTaskWithRequest(request, progress: nil, destination: nil, completionHandler: nil)
        
        task.taskDescription = UploadTaskDescription.VideoSettings.rawValue
        
        return task
    }

    public func videoSettingsDataTask(videoUri: String, videoSettings: VideoSettings, completionHandler: VideoCompletionHandler) throws -> URLSessionDataTask
    {
        let request = try (self.requestSerializer as! VimeoRequestSerializer).videoSettingsRequestWithUri(videoUri, videoSettings: videoSettings)
        
        let task = self.dataTaskWithRequest(request, completionHandler: { (response, responseObject, error) -> Void in
            
            // Do model parsing on a background thread
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), { [weak self] () -> Void in
                
                guard let strongSelf = self else
                {
                    return
                }

                do
                {
                    let video = try (strongSelf.responseSerializer as! VimeoResponseSerializer).processVideoSettingsResponse(response, responseObject: responseObject, error: error)
                    completionHandler(video: video, error: nil)
                }
                catch let error as NSError
                {
                    completionHandler(video: nil, error: error)
                }
            })
        })
        
        task.taskDescription = UploadTaskDescription.VideoSettings.rawValue
        
        return task
    }
    
    func deleteVideoDataTask(videoUri: String, completionHandler: @escaping ErrorBlock) throws -> URLSessionDataTask
    {
        let request = try (self.requestSerializer as! VimeoRequestSerializer).deleteVideoRequestWithUri(videoUri)
        
        let task = self.dataTaskWithRequest(request, completionHandler: { [weak self] (response, responseObject, error) -> Void in
            
            guard let strongSelf = self else
            {
                return
            }
            
            do
            {
                try (strongSelf.responseSerializer as! VimeoResponseSerializer).processDeleteVideoResponse(response, responseObject: responseObject, error: error)
                completionHandler(error: nil)
            }
            catch let error as NSError
            {
                completionHandler(error: error)
            }
        })
        
        task.taskDescription = UploadTaskDescription.DeleteVideo.rawValue
        
        return task
    }

    func videoDataTask(videoUri: String, completionHandler: VideoCompletionHandler) throws -> URLSessionDataTask
    {
        let request = try (self.requestSerializer as! VimeoRequestSerializer).videoRequestWithUri(videoUri)
        
        let task = self.dataTaskWithRequest(request, completionHandler: { [weak self] (response, responseObject, error) -> Void in
            
            guard let strongSelf = self else
            {
                return
            }
            
            do
            {
                let video = try (strongSelf.responseSerializer as! VimeoResponseSerializer).processVideoResponse(response, responseObject: responseObject, error: error)
                completionHandler(video: video, error: nil)
            }
            catch let error as NSError
            {
                completionHandler(video: nil, error: error)
            }
        })
        
        task.taskDescription = UploadTaskDescription.Video.rawValue
        
        return task
    }
}
