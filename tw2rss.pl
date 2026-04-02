#!/usr/bin/python3
"""
GGI script - Generate RSS feed from twitter user
query parameters:
  u = username
  l = limit of items
  r = for all tweets and replies
defaults to @nasa, 10 items and no replies
(replies query may have a heavier rate-limit) 
ex: http://host/cgi-bin/tw2rss?u=NWS&r=1
"""
import sys
import sqlite3
import json
import requests
import argparse
import datetime
import random
import time
import re
import warnings
from random import randint
from time import sleep

sleep(randint(1,20))

with warnings.catch_warnings():
    warnings.filterwarnings("ignore",category=DeprecationWarning)
    import cgi

connection = sqlite3.connect('/usr/local/share/db/twitter.db')
idcheck=connection.cursor()
auths = [
    "12412320fadf",
    "fasdfk323423",
    "all_auth_tokens_here"
]

ct0 = os.urandom(16).hex()
auth_token = random.choice(auths)

HEADERS = {
  'authorization': 'Bearer AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F',
  'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64; rv:146.0) Gecko/20100101 Firefox/146.0',
  'x-csrf-token': ct0,
  'cookie': 'ct0=' + ct0 + '; auth_token=' + auth_token 
}

# change to nitter instance
TWEET_URL = 'http://nitter'

###
FEATURES_USER = '{"hidden_profile_likes_enabled":false,"hidden_profile_subscriptions_enabled":true,"responsive_web_graphql_exclude_directive_enabled":true,"verified_phone_label_enabled":false,"subscriptions_verification_info_is_identity_verified_enabled":false,"subscriptions_verification_info_verified_since_enabled":true,"highlights_tweets_tab_ui_enabled":true,"creator_subscriptions_tweet_preview_api_enabled":true,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"responsive_web_graphql_timeline_navigation_enabled":true}'
FEATURES_TWEETS = '{"creator_subscriptions_tweet_preview_api_enabled":false,"communities_web_enable_tweet_community_results_fetch":false,"c9s_tweet_anatomy_moderator_badge_enabled":false,"articles_preview_enabled":false,"tweetypie_unmention_optimization_enabled":false,"responsive_web_edit_tweet_api_enabled":false,"graphql_is_translatable_rweb_tweet_is_translatable_enabled":false,"view_counts_everywhere_api_enabled":false,"longform_notetweets_consumption_enabled":false,"responsive_web_twitter_article_tweet_consumption_enabled":false,"tweet_awards_web_tipping_enabled":false,"creator_subscriptions_quote_tweet_preview_enabled":false,"freedom_of_speech_not_reach_fetch_enabled":false,"standardized_nudges_misinfo":false,"tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled":false,"tweet_with_visibility_results_prefer_gql_media_interstitial_enabled":false,"rweb_video_timestamps_enabled":false,"longform_notetweets_rich_text_read_enabled":true,"longform_notetweets_inline_media_enabled":true,"rweb_tipjar_consumption_enabled":false,"responsive_web_graphql_exclude_directive_enabled":false,"verified_phone_label_enabled":false,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"responsive_web_graphql_timeline_navigation_enabled":false,"responsive_web_enhance_cards_enabled":false,"rweb_lists_timeline_redesign_enabled":false,"responsive_web_media_download_video_enabled":false}'

GET_USER_URL = 'https://x.com/i/api/graphql/SAMkL5y_N9pmahSw8yy6gw/UserByScreenName'
GET_TWEETS_URL = 'https://x.com/i/api/graphql/XicnWRbyQ3WgVY__VataBQ/UserTweets'
GET_TWEETS_AND_REPLIES_URL= 'https://x.com/i/api/graphql/-gxtzCQbBPmOwxnY-SbiHQ/UserTweetsAndReplies'

FIELDNAMES = ['id', 'tweet_url', 'name', 'user_id', 'username', 'published_at', 'content', 'views_count', 'retweet_count', 'likes', 'quote_count', 'reply_count', 'bookmarks_count', 'medias']

class TwitterScraper:

    def __init__(self, username):
        self.HEADERS = HEADERS
        assert username
        self.username = username
        #print(f"DEBUG: {auth_token} username = {self.username}", file=sys.stderr)

    def get_user(self):
        arg = {"screen_name": self.username, "withSafetyModeUserFields": True}
        params = {
            'variables': json.dumps(arg),
            'features': FEATURES_USER,
        }
        
        response = requests.get(
            GET_USER_URL,
            params=params, 
            headers=self.HEADERS
        )
        
        try: 
            json_response = response.json()
        except requests.exceptions.JSONDecodeError: 
            print(response.status_code)
            print(response.text)
            raise

        result = json_response["data"]["user"]["result"]
        legacy = result["legacy"]

        return {
            "id": result["rest_id"],
            "username": legacy["screen_name"],
            "full_name": legacy["name"]
        }

    def tweet_parser(
            self,
            user_id, 
            full_name, 
            rest_id, 
            item_result, 
            legacy
        ):

        medias = legacy["entities"].get("media")
        medias = ", ".join(["%s (%s)" % (d["media_url_https"], d['type']) for d in medias]) if medias else ""
        urls = legacy["entities"].get("urls")
        urls = (
            ", ".join(
                x.get("expanded_url", "")
                for x in legacy.get("entities", {}).get("urls", [])
                if x.get("expanded_url")
            )
        )
        # Customize feed elements. Some may not be suited for RSS.
        return {
            "id": rest_id,
            "tweet_url": f"{TWEET_URL}/{self.username}/status/{rest_id}",
            "name": full_name,
            "user_id": user_id,
            "username": self.username,
            "published_at": legacy["created_at"],
            "content": legacy["full_text"],
            "urls": urls,
            "views_count": item_result.get("views", {}).get("count"),
            "retweet_count": legacy["retweet_count"],
            "likes": legacy["favorite_count"],
            "quote_count": legacy["quote_count"],
            "reply_count": legacy["reply_count"],
            "bookmarks_count": legacy["bookmark_count"],
            "medias": medias
        }

    def iter_tweets(self, replies, limit):
        _user = self.get_user()
        full_name = _user.get("full_name")
        user_id = _user.get("id")
        if not user_id:
            print("/!\\ error: no user id found")
            raise NotImplementedError
        cursor = None
        _tweets = []

        while True:
            var = {
                "userId": user_id, 
                "count": limit, 
                "cursor": cursor,
                "withTweetQuoteCount": True,
                "withQuickPromoteEligibilityTweetFields": False,
                "withSuperFollowsUserFields": False,
                "withSuperFollowsTweetFields": False,
                "withDownvotePerspective": False,
                "withReactionsMetadata": False,
                "includePromotedContent": False,
                "withReactionsPerspective": False,
                "withUserResults": False,
                "withVoice": True,
                "withNonLegacyCard": True,
                "withV2Timeline": True
            }

            params = {
                'variables': json.dumps(var),
                'features': FEATURES_TWEETS,
            }

            if replies:
                get_url = GET_TWEETS_AND_REPLIES_URL
            else:
                get_url = GET_TWEETS_URL

            response = requests.get(
                get_url,
                params=params,
                headers=self.HEADERS
            )

            json_response = response.json()
            # XXX
            #print(json.dumps(json_response))
            result = response.json()['data']['user']['result']
            timeline = result["timeline_v2"]["timeline"]["instructions"]
            entries = [x["entries"] for x in timeline if x["type"] == "TimelineAddEntries"]
            entries = entries[0] if entries else []

            for entry in entries:
                content = entry["content"]
                entry_type = content["entryType"]
                if entry['entryId'].startswith('tweet'):
                    item_result = content['itemContent']['tweet_results']['result']
                    
                    if 'legacy' not in item_result:
                        continue
                    
                    legacy = item_result["legacy"]
                    tweet_id = content["itemContent"]["tweet_results"]["result"]["rest_id"]
                    
                    tweet_data = self.tweet_parser(user_id, full_name, tweet_id, item_result, legacy)
                    _tweets.append(tweet_data)
                
                if entry['entryId'].startswith('profile-conversation'):
                    threads = [content["items"]]
                    threads = threads[0] if threads else []
                    for thread in threads:
                        thread_result = thread['itemContent']['tweet_results']['result']
                        legacy = thread_result["legacy"]
                        tweet_id = thread["item"]["itemContent"]["tweet_results"]["result"]["rest_id"]
                        if tweet_id:
                            tweet_data = self.tweet_parser(user_id, full_name, tweet_id, item_result, legacy)
                            _tweets.append(tweet_data)

                if entry_type == "TimelineTimelineCursor" and content.get("cursorType") == "Bottom":
                    cursor = content.get("value")


                if len(_tweets) >= limit:
                    break

            if len(_tweets) >= limit or cursor is None or len(entries) == 2:
                break

        return _tweets

    def generate_rss(self, username, tweets=[]):
        
        rss = """\
<?xml version="1.0" encoding="UTF-8" ?>
<rss version="2.0">

<channel>
<title>{} - RSS Feed</title>
<link>https://twitter.com/{}</link>
<description>Twitter Feed for @{}</description>
""".format(username, username, username)
        tweets = sorted(tweets, key=lambda x: x['id'], reverse=True)
        limit_trimmed = 15
        for t in tweets[:limit_trimmed]:
            tweet_id = t['id']
            user = t['username']
            content = t['content']
            twid = idcheck.execute("SELECT count(*) FROM tweets WHERE id = ?", (tweet_id,))
            data=twid.fetchone()[0]
            if data==0:
                idcheck.execute("INSERT into tweets (user,content,id) values (?,?,?)", (user,content,tweet_id,))
                connection.commit()
            
            rss += """\
<item>
    <title>{}</title>
    <author>@{}</author>
    <description>{}</description>
    <link>{}</link>
    <pubDate>{}</pubDate>
</item>
""".format(
        f"{t['content']} {t['medias']} {t['urls']}".strip(),
        username,        
        f"{t['content']} {t['medias']} {t['urls']}".strip(),
        f"{t['tweet_url']}",
        f"{t['published_at']}"
    )
        rss += "</channel>\n</rss>"
        print("Content-type: application/rss+xml")
        print("Cache-control: public, max-age=4000")
        print("Access-Control-Allow-Origin: *\n")
        print(rss)

def main():
    form = cgi.FieldStorage()
    username = "elonmusk"
    replies = None
    limit = 20
    if "u" in form:
      username = form["u"].value
    if "r" in form:
      replies = True
    if "l" in form:
      limit = int(form["l"].value)

    assert all([username, limit])

    twitter_scraper = TwitterScraper(username)
    tweets = twitter_scraper.iter_tweets(replies, limit=limit)
    assert tweets
    twitter_scraper.generate_rss(username, tweets)

if __name__ == '__main__':
    main()
