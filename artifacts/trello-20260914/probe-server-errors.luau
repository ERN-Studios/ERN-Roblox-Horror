local errors={}
for _,entry in ipairs(game:GetService("LogService"):GetLogHistory()) do
 if entry.messageType==Enum.MessageType.MessageError then
  table.insert(errors,{message=entry.message,time=entry.timestamp})
 end
end
return {errors=errors}
