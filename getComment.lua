Handlers.add(
   "GET_COMMENTS", -- Handler name
    "GET_COMMENTS", -- Pattern matcher function
   function(msg) -- Handler logic
        
       local postId = msg.Tags.post_id             -- Optional: Fetch comments for a specific post
       local parentCommentId = msg.Tags.parent_comment_id -- Optional: Fetch replies to a specific comment
       local limit = tonumber(msg.Tags.limit) or 50 -- Default limit is 50
       local cursor = msg.Tags.cursor              -- Optional: Cursor for pagination
       local sortBy = msg.Tags.sortBy or "latest"  -- Sorting order, default "latest"

       -- Validate limit
       if limit > 1000 then
           msg.reply({
               Data = json.encode({
                   status = "error",
                   message = "Limit cannot exceed 1000"
               })
           })
           return
       end

       -- Base query
       local query = "SELECT * FROM comments"
       local params = {}

       -- Add filters for post_id and parent_comment_id
       local conditions = {}
       if postId then
           table.insert(conditions, "post_id = ?")
           table.insert(params, postId)
       end
       if parentCommentId then
           table.insert(conditions, "parent_comment_id = ?")
           table.insert(params, parentCommentId)
       end

       -- Add cursor for pagination
       if cursor then
           if sortBy == "latest" then
               table.insert(conditions, "comment_id < ?")
           else
               table.insert(conditions, "comment_id > ?")
           end
           table.insert(params, cursor)
       end

       -- Append conditions to query
       if #conditions > 0 then
           query = query .. " WHERE " .. table.concat(conditions, " AND ")
       end

       -- Add sorting
       query = query .. (sortBy == "latest" and " ORDER BY comment_id DESC" or " ORDER BY comment_id ASC")

       -- Add limit
       query = query .. " LIMIT ?"
       table.insert(params, limit)

       -- Execute the query
       local comments = admin:select(query, params)

       -- Get the next cursor if there are more comments
       local nextCursor = #comments == limit and comments[#comments].comment_id or nil

       -- Parse comment_extra_data for each comment
       for _, comment in ipairs(comments) do
           comment.comment_extra_data = json.decode(comment.comment_extra_data or "{}")
       end

       -- Reply with the data
       msg.reply({
           Data = json.encode({
               status = "success",
               data = {
                   comments = comments,
                   next_cursor = nextCursor,
                   total_count = #comments,
                   has_more = nextCursor ~= nil
               }
           })
       })
   end
)