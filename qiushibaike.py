#!/usr/bin/env python
#-*- coding: utf-8 -*-
__author__ = 'dcje'

import urllib, urllib2, re, thread, time

class QSBK(object):
    def __init__(self):
        self.baseurl = 'http://www.qiushibaike.com/hot/'
        self.pageIdx = 1
        self.user_agent = 'Mozilla/5.0 (Windows NT 6.1; Win64; x64) \
            AppleWebKit/537.36 (KHTML, like Gecko) Chrome/56.0.2924.87 Safari/537.36 \
            Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
        self.headers = { 'User-Agent': self.user_agent}
        self.stories = []
        self.enable = False
        self.start()

    def getPage(self, pageIdx):
        url = self.baseurl + str(pageIdx)
        request = urllib2.Request(url, headers = self.headers)
        try:
            response = urllib2.urlopen(request)
            page = response.read().decode('utf-8')
            return page
        except urllib2.URLError, e:
            if hasattr(e, 'reason'):
                print 'failed connecting to qiushibaike: ',e.reason
                return None

    def getPageItems(self, pageIdx):
        page = self.getPage(pageIdx)
        if not page:
            print 'failed loading...'
            return None
        pattern = re.compile(r'<div class=["\']article.*?["\'] id=["\']qiushi_tag_(\d+)["\']>' +
            r'.*?<div class=["\']author.*?["\']>.*?title=["\'](?P<author>.*?)["\']>.*?<h2>(?P=author)' + 
            r'.*?<div class=["\']content.*?["\']>.*?<span>(.*?)</span>' + 
            r'.*?<div class="stats.*?class="number">(.*?)</i>', re.S)
        items = pattern.findall(page)
        pageStories = []
        replaceBR = re.compile(r'<br\s*/>')
        for item in items:
            text = replaceBR.sub("\n", item[2])
            pageStories.append( (item[0], item[1], text, item[3]) )
        return pageStories
    
    def loadPage(self):
        if self.enable and len(self.stories) < 2:
            pageStories = self.getPageItems(self.pageIdx)
            if pageStories:
                self.stories.extend(pageStories)
                self.pageIdx += 1

    def getOneStory(self, story, page):
        input = raw_input()
        self.loadPage()
        if 'Q' == input.strip().upper():
            self.enable = False
            return
        print 'page:%s\tid:%s\tauthor:%s\tup:%s\n%s' % (page, story[0], story[1], story[3], story[2])
        
    def start(self):
        print 'loading...press <Q> to exit'
        self.enable = True
        self.loadPage()
        while self.enable:
            if len(self.stories) > 0:
                self.getOneStory(self.stories.pop(0), self.pageIdx-1)

spider = QSBK()
