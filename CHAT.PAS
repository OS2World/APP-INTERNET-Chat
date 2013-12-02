uses use32, sock, os2base, os2def, crt, strings, strstf;

type
  userrec = record
    nick: string;
    socket: integer;
    host: string;
  end;

const
  maxusers = 50;

var
  lsock, csock: integer;
  server, client: sockaddr_in;
  threadid, i: integer;
  li: longint;
  chatport: ushort;
  c: char;
  csema: hmtx;
  user: array[1..maxusers] of userrec;
  numusers: byte;
  ip: phostent;
  s: string;
  topic: string;

function pad(p, p1: string; spaces: integer): string;
var
  i: integer;
begin
  for i:=length(p) to spaces do
    p:=p+' ';
  p:=p+p1;
  pad:=p;
end;

procedure sendtoall(s: string);
var i: integer;
begin
  dosrequestmutexsem(csema, sem_Indefinite_Wait);
  for i:=1 to numusers do
    sendstring(user[i].socket, s+crlf);
  dosreleasemutexsem(csema);
end;

procedure addnick(sock: integer; nick: string);
var i: integer;
begin
  for i:=1 to numusers do
    if user[i].socket = sock then user[i].nick:=nick;
end;

procedure delnick(nick: string);
var i, j: integer;
begin
  for i:=1 to numusers do
    if scmp(user[i].nick, nick) then
      begin
        for j:=i+1 to numusers do
          move(user[j], user[j-1], sizeof(user[j]));
      end;
  dec(numusers);
  for i:=numusers+1 to maxusers do
    fillchar(user[i], sizeof(user[i]), #0);
end;

function checkuser(nick: string): boolean;
var i: integer;
begin
  for i:=1 to numusers do
    if scmp(nick, user[i].nick) then
      begin
        checkuser:=true;
        exit;
      end else checkuser:=false;
end;

function cleanstr(s: string): string;
var
  i: integer;
  s1: string;
begin
  while pos(#8, s)>0 do delete(s, pos(#8, s)-1, 2);
  while pos(#127, s)>0 do delete(s, pos(#8, s)-1, 2);
  s1:='';
  for i:=1 to length(s) do
    if s[i] in [' '..'~'] then s1:=s1+s[i];
  cleanstr:=s1;
end;

function chat(p: pointer): integer;
var
  nick: string;
  chatsock: integer;
  buf: array[1..512] of char;
  buflen, i: integer;
  dead, gotnick: boolean;
  s, cmd: string;
begin
  chatsock:=integer(p^);
  sendstring(chatsock, 'Welcome to dink''s chatter!'+crlf);
  gotnick:=false;
  sendstring(chatsock, 'input your name: ');
  repeat
    if getstr(chatsock, @buf, 250, dead) then
      begin
        s:=cleanstr(truncstr(strpas(@buf)));
        if length(s)>20 then
          begin
            sendstring(chatsock, 'YEESH!  keep it under 20 characters.'+crlf);
            sendstring(chatsock, 'input your name: ');
          end else
        if length(s)=0 then
          begin
            sendstring(chatsock, 'You must enter SOMETHING!'+crlf);
            sendstring(chatsock, 'input your name: ');
          end else
        if checkuser(s)=false then
          begin
            nick:=s;
            addnick(chatsock, nick);
            gotnick:=true;
          end else
          begin
            sendstring(chatsock, 'Someone is allready using that name!'+crlf);
            sendstring(chatsock, 'input your name: ');
          end;
      end else dossleep(1);
  until gotnick or dead;
  if dead then
    begin
      str(chatsock, s);
      delnick('new'+s);
      soclose(chatsock);
      exit;
    end;
  sendtoall('* '+nick+' Has entered the chatter!');
  sendstring(chatsock, 'Type /help to get... help!'+crlf);
  if topic<>'' then sendstring(chatsock, 'The topic is: '+topic+crlf);
  repeat
    if getstr(chatsock, @buf, 250, dead) then
      begin
        s:=cleanstr(truncstr(strpas(@buf)));
        if s[1]='/' then
          begin
            delete(s, 1, 1);
            cmd:=token(' ', s);
            s:=truncstr(s);
            if scmp('WHO', cmd) then
              begin
                sendstring(chatsock, 'User Listing'+crlf+'------------'+crlf);
                for i:=1 to numusers do
                  sendstring(chatsock, pad(user[i].nick, '('+user[i].host+')', 20)+crlf);
                sendstring(chatsock, '------------'+crlf);
              end else
            if scmp('QUIT', cmd) or scmp('BYE', cmd) or scmp('EXIT', cmd) then
              begin
                sendstring(chatsock, 'Cya later..'+crlf);
                dead:=true;
              end else
            if scmp('HELP', cmd) or scmp('?', cmd) then
              begin
                sendstring(chatsock, 'Available commands:'+crlf);
                sendstring(chatsock, '  /who   - display whos currently online'+crlf);
                sendstring(chatsock, '  /topic - change the topic'+crlf);
                sendstring(chatsock, '  /bye   - get outta here!'+crlf);
                sendstring(chatsock, '-------------------'+crlf);
              end else
            if scmp('TOPIC', cmd) or scmp('T', cmd) then
              begin
                if s<>'' then
                  begin
                    topic:=s;
                    sendtoall('* '+nick+' Has changed the topic to: '+topic);
                  end else sendstring(chatsock, 'usage: /topic <the topic>'+crlf);
              end else
                sendstring(chatsock, 'Thats not a command!  Try /help'+crlf);
          end else
        if (s<>'') then sendtoall('<'+nick+'> '+s);
      end else dossleep(1);
  until dead=true;
  sendtoall('* '+nick+' Has now left the building!');
  soclose(chatsock);
  delnick(nick);
end;

begin
  if paramcount=0 then
    begin
      writeln('usage: chat.exe <port>');
      halt;
    end;
  val(paramstr(1), i, li);
  if li=0 then chatport:=i else
    begin
      writeln('port specified on command line is invalid!');
      writeln('use a number between 1024 and 64738.');
      halt;
    end;
  lsock:=socket(af_inet, sock_stream, 0);
  fillchar(server, sizeof(server), #0);
  server.sin_family:=af_inet;
  server.sin_port:=htons(chatport);
  server.sin_addr.s_addr:=inaddr_any;
  if (bind(lsock, server, sizeof(server))<>0) then
    begin
      psock_errno('bind()');
      halt;
    end;
  listen(lsock, 5);

  fillchar(user, sizeof(user), #0);
  numusers:=0;
  topic:='';
  doscreatemutexsem(nil, csema, 0, False);

  writeln('chat server active on port ', chatport);
  writeln('hit ctrl-c to quit.');

  i:=sizeof(client);
  repeat
    csock:=accept(lsock, client, i);
    inc(numusers);
    user[numusers].socket:=csock;
    user[numusers].host:=inet_ntos(client.sin_addr.s_addr);
    str(csock, s);
    user[numusers].nick:='new'+s;
    ip := gethostbyaddr(@client.sin_addr.s_addr, sizeof(ulong), AF_INET);
    if ip<>nil then user[numusers].host:=strpas(ip^.h_name);

    BeginThread(nil, 20*1024, chat, @csock, create_Ready, threadid);
  until 1=2;
end.

