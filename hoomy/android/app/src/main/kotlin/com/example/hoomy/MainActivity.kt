package com.example.hoomy

import com.ryanheise.audioservice.AudioServiceActivity

// 继承 AudioServiceActivity：audio_service 要求 Activity 提供它需要的
// FlutterEngine（ADR-0008），否则后台播放的媒体会话初始化会抛异常。
class MainActivity : AudioServiceActivity()
