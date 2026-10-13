//
//  texture_helper.m
//  IntroOpenGL
//
//  Created by Ilya Rimchikov on 11/03/14.
//  Copyright (c) 2014 Learn OpenGL ES. All rights reserved.
//

#include "texture_helper.h"

#import <UIKit/UIKit.h>

GLuint setup_texture(NSString *fileName, UIColor *color)
{
    (void)color;
    // The opening page shares the generated main-bundle AyuGram icon.
    // Its logo is complete, so the old animated lightning layer is transparent.
    BOOL ayuLogo = [fileName isEqualToString:@"telegram_sphere.png"];
    BOOL ayuOldPlane = [fileName isEqualToString:@"telegram_plane1.png"];
    UIImage *image;
    if (ayuOldPlane) {
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
        format.opaque = NO;
        format.scale = 1.0;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(1, 1) format:format];
        image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) { (void)context; }];
    } else {
        image = [UIImage imageNamed:ayuLogo ? @"AyuClassic@3x.png" : fileName];
    }
    CGImageRef spriteImage = image.CGImage;
    if (!spriteImage) {
        NSLog(@"Failed to load image %@", fileName);
        return -1;
    }

    
    // 2
    size_t width = CGImageGetWidth(spriteImage);
    size_t height = CGImageGetHeight(spriteImage);
    
    GLubyte * spriteData = (GLubyte *) calloc(width*height*4, sizeof(GLubyte));
    
    CGContextRef spriteContext = CGBitmapContextCreate(spriteData, width, height, 8, width*4, CGImageGetColorSpace(spriteImage), (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    
    // 3
    if (ayuLogo) {
        CGFloat radius = MIN(width, height) * 0.22;
        CGPathRef path = CGPathCreateWithRoundedRect(CGRectMake(0, 0, width, height), radius, radius, NULL);
        CGContextAddPath(spriteContext, path);
        CGContextClip(spriteContext);
        CGPathRelease(path);
    }
    CGContextDrawImage(spriteContext, CGRectMake(0, 0, width, height), spriteImage);
    
    CGContextRelease(spriteContext);
    
    // 4
    GLuint texName;
    
    glGenTextures(1, &texName);
    glBindTexture(GL_TEXTURE_2D, texName);
    
    
    // use linear filetring
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
    // clamp to edge
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, (GLsizei)width, (GLsizei)height, 0, GL_RGBA, GL_UNSIGNED_BYTE, spriteData);
    
    free(spriteData);
    return texName;
}



