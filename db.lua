-- this code here is used to initialize the AO databse tables!


-- this creates the databse

local sqlite3 = require("lsqlite3")
local dbAdmin = require("@rakis/DbAdmin")

-- Open an in-memory database
db = sqlite3.open_memory()

-- Create a DbAdmin instance
admin = dbAdmin.new(db)



-- this creates user table

admin:exec([[
  CREATE TABLE users (
    user_id INTEGER PRIMARY KEY AUTOINCREMENT,
    address TEXT UNIQUE NOT NULL,
    username TEXT UNIQUE NOT NULL,
    full_name TEXT NOT NULL,
    description TEXT,
    profile_picture_url TEXT,
    cover_photo_url TEXT,
    profile_extra_data TEXT,  -- This will store JSON data
    is_verified INTEGER DEFAULT 0, -- SQLite doesn't have boolean, uses 0/1
    last_login_at DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
]])



-- this creaets posts table


admin:exec([[
 CREATE TABLE posts (
   post_id INTEGER PRIMARY KEY AUTOINCREMENT,
   address TEXT,
   content TEXT,
   media_urls TEXT,
   post_extra_data TEXT,
   visibility TEXT DEFAULT 'public',
   is_edited INTEGER DEFAULT 0, 
   view_count INTEGER DEFAULT 0,
    
   created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
   updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
   FOREIGN KEY (address) REFERENCES users(address)
 );
]])


-- this creates comments table

admin:exec([[
 CREATE TABLE comments (
   comment_id INTEGER PRIMARY KEY AUTOINCREMENT,
   post_id INTEGER,
   user_id INTEGER,
   content TEXT NOT NULL,
   parent_comment_id INTEGER,
   comment_extra_data TEXT,
   is_edited INTEGER DEFAULT 0,
   created_at DATETIME DEFAULT CURRENT_TIMESTAMP,

   FOREIGN KEY (post_id) REFERENCES posts(post_id) ON DELETE CASCADE,
   FOREIGN KEY (user_id) REFERENCES users(user_id),
   FOREIGN KEY (parent_comment_id) REFERENCES comments(comment_id)
 );
]])


--  this creates likes table


admin:exec([[
 CREATE TABLE likes (
   user_id INTEGER,
   post_id INTEGER,
   created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
   PRIMARY KEY (user_id, post_id),
   FOREIGN KEY (user_id) REFERENCES users(user_id),
   FOREIGN KEY (post_id) REFERENCES posts(post_id) ON DELETE CASCADE
 );
]])

-- for hashtags

admin:exec([[
 CREATE TABLE hashtags (
   hashtag_id INTEGER PRIMARY KEY AUTOINCREMENT,
   name TEXT UNIQUE NOT NULL,
   created_at DATETIME DEFAULT CURRENT_TIMESTAMP
 );
]])

admin:exec([[
 CREATE TABLE post_hashtags (
   post_id INTEGER,
   hashtag_id INTEGER,
   PRIMARY KEY (post_id, hashtag_id),
   FOREIGN KEY (post_id) REFERENCES posts(post_id) ON DELETE CASCADE,
   FOREIGN KEY (hashtag_id) REFERENCES hashtags(hashtag_id)
 );
]])



-- notifications 

admin:exec([[
  CREATE TABLE notifications (
    notification_id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER,
    type VARCHAR(50) NOT NULL,
    actor_id INTEGER,
    notification_extradata TEXT,
    reference_id INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    FOREIGN KEY (actor_id) REFERENCES users(user_id)
  );
]])


-- after all tables are created, index them 

admin:exec("CREATE INDEX idx_posts_user_id ON posts(address);")
admin:exec("CREATE INDEX idx_comments_post_id ON comments(post_id);")
admin:exec("CREATE INDEX idx_comments_user_id ON comments(user_id);")
admin:exec("CREATE INDEX idx_likes_post_id ON likes(post_id);")