unit uhttpdownload;

{$mode objfpc}{$H+}
{
  ****************************************************************************
                               uhttpdownload Unit
          Threaded download with progress details using Synapse Library
                    (c) 2016 by Dio Affriza under BSD License
  ****************************************************************************
}
interface

uses
  Classes, SysUtils, FileUtil, httpsend, blcksock, typinfo, Math, Dialogs, ssl_openssl_lib, ssl_openssl;

type
  THTTPDownloader = class;

  TNoPresizeFileStream = class(TFileStream)
    procedure SetSize(const NewSize: int64); override;
  end;

  TOnReadyEvent =
    procedure(Sender: TObject; AMsg: string; ABytes, AMaxBytes: longint) of object;

  THTTPDownloadThread = class(TThread)
  public
    constructor Create(Owner: THTTPDownloader; URL, TargetFile, RqRangeVal: string;
      fOnReady: TOnReadyEvent);
  protected
    procedure Execute; override;
  private
    ffOwner: THTTPDownloader;
    ffOnReady: TOnReadyEvent;
    ffValue, ffRqRange: string;
    Bytes, MaxBytes: longint;
    fURL, fTargetFile: string;
    exitd: boolean;
    procedure Ready;
  end;

  THTTPDownloader = class(TComponent)
  private
    DownloadThread: THTTPDownloadThread;
    fOnReady: TOnReadyEvent;
    fStarted: boolean;
    fRqRange: string;
    fFileName, fURL: string;
    // Variables just like a drops of a shit. But this is Pascal
    // Only look at top declaration to see all variables
    procedure setURL(Value: string);
    procedure setFileName(Value: string);
    procedure setRqRange(Value: string);
  public
    constructor Create(AOwner: TComponent); override;
    procedure Start;
    procedure Stop;
  published
    property OnReady: TOnReadyEvent read fOnReady write fOnReady;
    property URL: string read fURL write setURL;
    property FileName: string read fFileName write setFileName;
    property RqRange: string read fRqRange write setRqRange;
  end;

implementation

procedure Split(const Delimiter: char; Input: string; const Strings: TStrings);
begin
  Assert(Assigned(Strings));
  Strings.Clear;
  Strings.StrictDelimiter := True;
  Strings.Delimiter := Delimiter;
  Strings.DelimitedText := Input;
end;

procedure TNoPresizeFileStream.SetSize(const NewSize: int64);
begin
end;

// Downloader Component Class

constructor THTTPDownloader.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  fRqRange := '0-0';
end;

procedure THTTPDownloader.setRqRange(Value: string);
begin
  if Value = '' then
    fRqRange := '0-0'
  else
    fRqRange := Value;
end;

procedure THTTPDownloader.setURL(Value: string);
begin
  fURL := Value;
end;

procedure THTTPDownloader.setFileName(Value: string);
begin
  fFileName := Value;
end;

procedure THTTPDownloader.Start;
begin
  if not fStarted then
    DownloadThread := THttpDownloadThread.Create(Self, fURL, fFileName,
      fRqRange, fOnReady);
  DownloadThread.Start;
end;

procedure THTTPDownloader.Stop;
begin
  DownloadThread.Terminate;
  DownloadThread.WaitFor;
end;

// Thread of Downloads
procedure THTTPDownloadThread.Execute;
var
  HTTPGetResult: boolean;
  RangeInf: TStringList;
  i: integer;
  s: string;
  Result: boolean;
  HTTPSender: THTTPSend;
  HEADResult: longint;
  Buffer: TNoPreSizeFileStream;
begin
  RangeInf := TStringList.Create;
  split('-', ffRqRange, RangeInf);
  Result := False;
  Bytes := 0;
  MaxBytes := -1;
  exitd := False;
  HTTPSender := THTTPSend.Create;
  HTTPSender.UserAgent:='';
  ffValue := 'Sending HEAD';
  Synchronize(@Ready);
  HTTPSender.Sock.CreateWithSSL(TSSLOpenSSL);
  HTTPSender.Sock.SSLDoConnect;
  HTTPGetResult := HTTPSender.HTTPMethod('HEAD', fURL);
  for i := 0 to HTTPSender.Headers.Count - 1 do
  begin
    s := UpperCase(HTTPSender.Headers[i]);
    if pos('CONTENT-LENGTH:', s) > 0 then
      MaxBytes := StrToIntDef(copy(s, pos(':', s) + 1, length(s)), 0);
  end;
  HEADResult := HTTPSender.ResultCode;
  if (HEADResult >= 300) and (HEADResult <= 399) then
  begin
    showmessage('redirection'+#13+ 'Not implemented, but could be.');
    exitd := true;
  end
  else if (HEADResult >= 500) and (HEADResult <= 599) then
  begin
    showmessage('internal server error'+#13+
    'When you use HTTPS, try change to HTTP');
    exitd := true;
  end;
  HTTPSender.Free;
  ffValue := 'Sending GET';
  Synchronize(@Ready);
  if exitd = false then
  repeat
    HTTPSender := THTTPSend.Create;
    HTTPSender.UserAgent:='';
    HTTPSender.Sock.CreateWithSSL(TSSLOpenSSL);
    HTTPSender.Sock.SSLDoConnect;
    if not FileExists(fTargetFile) then
    begin
      Buffer := TNoPreSIzeFileStream.Create(fTargetFile, fmCreate);
    end
    else
    begin
      Buffer := TNoPreSIzeFileStream.Create(fTargetFile, fmOpenReadWrite);
      if not exitd then
        Buffer.Seek(Max(0, Buffer.Size - 4096), soFromBeginning);
    end;
    try
      if ffRqRange = '0-0' then
        HTTPSender.RangeStart := Buffer.Position
      else
        HTTPSender.RangeStart := StrToInt(RangeInf[0]);
      if ffRqRange = '0-0' then
      begin
        if not (Buffer.Size + 50000 >= MaxBytes) then
          HTTPSender.RangeEnd := Buffer.Size + 50000
        else

          HTTPSender.RangeEnd := Buffer.Size + (MaxBytes - Buffer.Size);
        HTTPGetResult := HTTPSender.HTTPMethod('GET', fURL);
      end
      else
      begin
        if not (Buffer.Size + 50000 >= StrToInt(RangeInf[1])) then
          HTTPSender.RangeEnd := Buffer.Size + 50000
        else
          HTTPSender.RangeEnd := Buffer.Size + (StrToInt(RangeInf[1]) - Buffer.Size);
        HTTPGetResult := HTTPSender.HTTPMethod('GET', fURL);
      end;
      if buffer.Size < MaxBytes then
        exitd := False
      else
        exitd := True;
      if (HTTPSender.ResultCode >= 100) and (HTTPSender.ResultCode <= 299) then
      begin
        HTTPSender.Document.SaveToStream(buffer);
        Result := True;
      end;
    finally
      Bytes := buffer.Position;
      HTTPSender.Free;
      buffer.Free;
    end;
    ffValue := 'Downloading';
    Synchronize(@Ready);
  until exitd or terminated;
  RangeInf.Free;
  if Result = True then
    ffValue := 'OK'
  else
    ffValue := 'Download failed';
  Synchronize(@Ready);
end;

constructor THTTPDownloadThread.Create(Owner: THTTPDownloader;
  URL, TargetFile, RqRangeVal: string; fOnReady: TOnReadyEvent);
begin
  fURL := URL;
  fTargetFile := TargetFile;
  inherited Create(True);
  ffOwner := Owner;
  ffRqRange := RqRangeVal;
  Priority := tpHigher;
  Suspended := False;
  ffOnReady := fOnReady;
  FreeOnTerminate := True;
end;

procedure THTTPDownloadThread.Ready;
begin
  if Assigned(ffOnReady) then
    ffOnReady(Self, ffValue, Bytes, MaxBytes);
end;

end.
