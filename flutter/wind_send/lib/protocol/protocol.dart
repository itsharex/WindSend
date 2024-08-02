import 'package:flutter/foundation.dart';

import 'dart:convert';
import 'dart:async';
import 'dart:io';

// import 'package:pasteboard/pasteboard.dart';

enum DeviceAction {
  copy("copy"),
  pasteText("pasteText"),
  pasteFile("pasteFile"),
  downloadAction("download"),
  webCopy("webCopy"),
  webPaste("webPaste"),
  syncText("syncText"),
  ping("ping"),
  matchDevice("match"),
  unKnown("unKnown");

  const DeviceAction(this.name);
  final String name;

  String toJson() => name;

  static DeviceAction fromJson(String json) {
    final String name = jsonDecode(json);
    return DeviceAction.values.firstWhere(
      (action) => action.name == name,
      orElse: () => DeviceAction.unKnown,
    );
  }

  static DeviceAction fromString(String name) {
    return DeviceAction.values.firstWhere(
      (action) => action.name == name,
      orElse: () => DeviceAction.unKnown,
    );
  }
}

enum DeviceUploadType {
  file("file"),
  dir("dir"),
  uploadInfo("uploadInfo"),
  unKnown("unKnown");

  const DeviceUploadType(this.name);
  final String name;

  String toJson() => name;

  static DeviceUploadType fromJson(String json) {
    final String name = jsonDecode(json);
    return DeviceUploadType.values.firstWhere(
      (type) => type.name == name,
      orElse: () => DeviceUploadType.unKnown,
    );
  }

  static DeviceUploadType fromString(String name) {
    return DeviceUploadType.values.firstWhere(
      (type) => type.name == name,
      orElse: () => DeviceUploadType.unKnown,
    );
  }
}

class HeadInfo {
  String deviceName;
  DeviceAction action;
  String timeIp;
  int fileID;
  int fileSize;
  DeviceUploadType uploadType;

  /// The file path for upload or download.
  /// For uploads, this is the relative path to upload to.
  /// For downloads, this is the path on the server to download from.
  String path;

  int start;
  int end;
  int dataLen;
  int opID;
  // int filesCountInThisOp;

  HeadInfo(this.deviceName, this.action, this.timeIp,
      {this.fileID = 0,
      this.fileSize = 0,
      this.uploadType = DeviceUploadType.unKnown,
      this.path = '',
      this.start = 0,
      this.end = 0,
      this.dataLen = 0,
      this.opID = 0});

  HeadInfo.fromJson(Map<String, dynamic> json)
      : deviceName = json['deviceName'],
        action = DeviceAction.fromString(json['action']),
        timeIp = json['timeIp'],
        fileID = json['fileID'],
        uploadType = DeviceUploadType.fromString(json['uploadType']),
        fileSize = json['fileSize'],
        path = json['path'],
        start = json['start'],
        end = json['end'],
        dataLen = json['dataLen'],
        opID = json['opID'];

  Map<String, dynamic> toJson() => {
        'deviceName': deviceName,
        'action': action,
        'timeIp': timeIp,
        'fileID': fileID,
        'uploadType': uploadType,
        'fileSize': fileSize,
        'path': path,
        'start': start,
        'end': end,
        'dataLen': dataLen,
        'opID': opID
      };

  Future<void> writeToConn(SecureSocket conn) async {
    var headInfojson = jsonEncode(toJson());
    var headInfoUint8 = utf8.encode(headInfojson);
    var headInfoUint8Len = headInfoUint8.length;
    var headInfoUint8LenUint8 = Uint8List(4);
    headInfoUint8LenUint8.buffer
        .asByteData()
        .setUint32(0, headInfoUint8Len, Endian.little);
    conn.add(headInfoUint8LenUint8);
    conn.add(headInfoUint8);
    // await conn.flush();
  }

  Future<void> writeToConnWithBody(SecureSocket conn, List<int> body) async {
    // dataLen = body.length;
    if (body.length != dataLen) {
      throw Exception('body.length != dataLen');
    }
    var headInfojson = jsonEncode(toJson());
    var headInfoUint8 = utf8.encode(headInfojson);
    var headInfoUint8Len = headInfoUint8.length;
    var headInfoUint8LenUint8 = Uint8List(4);
    headInfoUint8LenUint8.buffer
        .asByteData()
        .setUint32(0, headInfoUint8Len, Endian.little);
    conn.add(headInfoUint8LenUint8);
    conn.add(headInfoUint8);
    conn.add(body);
    // await conn.flush();
  }
}

class RespHead {
  int code;
  String dataType;
  String? timeIp;
  String? msg;
  // List<TargetPaths>? paths;
  int dataLen = 0;

  static const String dataTypeFiles = 'files';
  static const String dataTypeText = 'text';
  static const String dataTypeImage = 'clip-image';

  RespHead(this.code, this.dataType, {this.timeIp, this.msg, this.dataLen = 0});

  RespHead.fromJson(Map<String, dynamic> json)
      : code = json['code'],
        timeIp = json['timeIp'],
        msg = json['msg'],
        // paths = json['paths']?.cast<String>(),
        dataLen = json['dataLen'],
        dataType = json['dataType'];

  Map<String, dynamic> toJson() => {
        'code': code,
        'timeIp': timeIp,
        'msg': msg,
        'dataLen': dataLen,
        'dataType': dataType
      };

  /// return [head, body]
  /// 不适用于body过大的情况
  static Future<(RespHead, List<int>)> readHeadAndBodyFromConn(
      Stream<Uint8List> conn) async {
    int respHeadLen = 0;
    int bodyLen = 0;
    List<int> respContentList = [];
    RespHead? respHeadInfo;
    bool isHeadReading = true;
    await for (var data in conn) {
      respContentList.addAll(data);
      // print('addall respContentList.length: ${respContentList.length}');
      if (isHeadReading) {
        if (respHeadLen == 0 && respContentList.length >= 4) {
          respHeadLen =
              ByteData.sublistView(Uint8List.fromList(respContentList))
                  .getInt32(0, Endian.little);
        }
        if (respHeadLen != 0 && respContentList.length >= respHeadLen + 4) {
          var respHeadBytes = respContentList.sublist(4, respHeadLen + 4);
          var respHeadJson = utf8.decode(respHeadBytes);
          respHeadInfo = RespHead.fromJson(jsonDecode(respHeadJson));
          // print('respHeadInfo: ${respHeadInfo.toJson().toString()}');
          // if (respHeadInfo.code != 200) {
          //   return (respHeadInfo, <int>[]);
          // }
          bodyLen = respHeadInfo.dataLen;
          if (bodyLen == 0) {
            return (respHeadInfo, <int>[]);
          }
          // print('respContentList.length: ${respContentList.length}');
          respContentList = respContentList.sublist(respHeadLen + 4);
          // print('respContentList.length: ${respContentList.length}');
          isHeadReading = false;
        } else {
          continue;
        }
      }
      if (bodyLen != 0 && respContentList.length >= bodyLen) {
        var respBody = respContentList.sublist(0, bodyLen);
        return (respHeadInfo!, respBody);
      }
    }
    // The server may have actively closed the connection
    var errMsg = 'readHeadAndBodyFromConn error';
    if (respHeadInfo != null) {
      errMsg =
          '$errMsg, respHeadInfo: ${respHeadInfo.toJson().toString()},bodyLen: $bodyLen, bufferLen: ${respContentList.length}';
    }
    throw Exception(errMsg);
  }
}

class UploadOperationInfo {
  /// The total size of the file to upload for this operation
  int filesSizeInThisOp = 0;

  /// The number of files to upload for this operation
  int filesCountInThisOp = 0;

  /// files and dirs to upload for this operation
  Map<String, PathInfo>? uploadPaths;

  /// A collection of empty directories uploaded by this operation
  List<String>? emptyDirs;

  UploadOperationInfo(this.filesSizeInThisOp, this.filesCountInThisOp,
      {this.uploadPaths, this.emptyDirs});

  UploadOperationInfo.fromJson(Map<String, dynamic> json)
      : filesSizeInThisOp = json['filesSizeInThisOp'],
        filesCountInThisOp = json['filesCountInThisOp'],
        uploadPaths = json['uploadItems'],
        emptyDirs = json['emptyDirs'];

  Map<String, dynamic> toJson() => {
        'filesSizeInThisOp': filesSizeInThisOp,
        'filesCountInThisOp': filesCountInThisOp,
        'uploadPaths': uploadPaths,
        'emptyDirs': emptyDirs
      };
}

enum PathType {
  file("file"),
  dir("dir"),
  unKnown("unKnown");

  const PathType(this.name);
  final String name;

  String toJson() => name;

  static PathType fromJson(String json) {
    final String name = jsonDecode(json);
    return PathType.fromString(name);
  }

  static PathType fromString(String name) {
    return PathType.values.firstWhere(
      (type) => type.name == name,
      orElse: () => PathType.unKnown,
    );
  }
}

class PathInfo {
  String path = '';
  PathType type = PathType.unKnown;

  /// file or dir size in bytes
  int? size;

  PathInfo(this.path, {this.type = PathType.unKnown, this.size});

  PathInfo.fromJson(Map<String, dynamic> json)
      : path = json['path'],
        type = json['type'],
        size = json['size'];

  Map<String, dynamic> toJson() {
    Map<String, dynamic> data = {};
    data['path'] = path;
    data['type'] = type;
    data['size'] = size;
    return data;
  }
}

class DownloadInfo {
  /// 文件在服务端设备上的路径
  String remotePath;

  /// 文件在本地设备上的相对保存路径
  String savePath;

  /// 传输类型
  PathType type;
  // static const String pathInfoTypeFile = 'file';
  // static const String pathInfoTypeDir = 'dir';

  /// 文件大小(字节)，目录为0
  int size;

  DownloadInfo(this.remotePath, this.savePath, this.size,
      {this.type = PathType.file});

  DownloadInfo.fromJson(Map<String, dynamic> json)
      : remotePath = json['path'],
        savePath = json['savePath'],
        type = PathType.fromString(json['type']),
        size = json['size'];

  Map<String, dynamic> toJson() {
    Map<String, dynamic> data = {};
    data['path'] = remotePath;
    data['savePath'] = savePath;
    data['type'] = type;
    data['size'] = size;
    return data;
  }
}
