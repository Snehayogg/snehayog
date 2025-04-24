import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  _UploadScreenState createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  File? _videoFile;
  final picker = ImagePicker();
  bool isUploading = false;

  // Pick video from gallery
  Future<void> _pickVideo() async {
    final pickedFile = await picker.pickVideo(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _videoFile = File(pickedFile.path);
      });
    }
  }

  // Upload video to the backend
  Future<void> _uploadVideo() async {
    if (_videoFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No video selected')));
      return;
    }

    setState(() {
      isUploading = true;
    });

    try {
      String uploadUrl = 'http://192.168.0.192:5000/api/upload';
      FormData formData = FormData.fromMap({
        'video': await MultipartFile.fromFile(_videoFile!.path, filename: 'video.mp4'),
      });

      Dio dio = Dio();
      Response response = await dio.post(uploadUrl, data: formData);

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Video uploaded successfully')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error uploading video')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed')));
    } finally {
      setState(() {
        isUploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Upload Video"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (_videoFile != null)
              Container(
                padding: EdgeInsets.all(10),
                child: Text('Selected Video: ${_videoFile!.path.split('/').last}'),
              ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _pickVideo,
              child: Text('Pick Video'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: isUploading ? null : _uploadVideo,
              child: isUploading
                  ? CircularProgressIndicator()
                  : Text('Upload Video'),
            ),
          ],
        ),
      ),
    );
  }
}
