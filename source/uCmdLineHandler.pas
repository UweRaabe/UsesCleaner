unit uCmdLineHandler;

interface

uses
  System.Classes, System.SysUtils;

resourcestring
  SMayContainWildcards = 'may contain wildcards';
  SUsage = 'usage';
  SConverting = 'converting';
  SCanNotCreateFolder = 'can not create folder';
  SPressEnterToContinue = 'press <enter> to continue...';

type
  TProgressEvent = TProc<Integer>;
  TProgressHandler = class
  private
    FCount: Integer;
    FCurrent: Integer;
    FOnProgress: TProgressEvent;
    FProgress: Integer;
    procedure SetCount(const Value: Integer);
    procedure SetProgress(const Value: Integer);
  protected
    procedure DoProgress; virtual;
  public
    class function ConsoleProgressEvent: TProgressEvent;
    procedure Finished;
    procedure LinkToConsole;
    procedure Reset;
    procedure StepIt;
    property Count: Integer read FCount write SetCount;
    property Progress: Integer read FProgress write SetProgress;
    property OnProgress: TProgressEvent read FOnProgress write FOnProgress;
  end;

type
  TCmdLineHandler = class
  private
    FLogFileName: string;
    FLogs: TStringList;
    FOEMEncoding: TEncoding;
    FOutPath: string;
    FParams: TStringList;
    function GetSwitch(const Name: string): Boolean;
    procedure SaveLogFile(const FileName: string);
  protected
    function ChangeChar(const Value: string; Source, Target: Char): string;
    function ChangePath(const FileName, Path: string): string;
    function CleanPathName(const Value: string): string;
    function ExeName: string;
    function ExePath: string;
    procedure FinishHandler; virtual;
    function GetFileEncoding(const AFileName: string; ADefaultEncoding: TEncoding): TEncoding;
    procedure HandleCmdLine;
    procedure InternalHandleCmdLine; virtual; abstract;
    procedure LogError(const Value: string); virtual;
    procedure LogLine(const Value: string); virtual;
    procedure PrepareHandler; virtual;
    procedure ShowCmdLine; virtual; abstract;
  public
    constructor Create; virtual;
    destructor Destroy; override;
    class procedure Execute; virtual;
    function SwitchValue(const Name: string; const Default: string = ''): string;
    class procedure WaitForKeyPress;
    property LogFileName: string read FLogFileName write FLogFileName;
    property Logs: TStringList read FLogs;
    property OEMEncoding: TEncoding read FOEMEncoding;
    property OutPath: string read FOutPath write FOutPath;
    property Params: TStringList read FParams;
    property Switch[const Name: string]: Boolean read GetSwitch;
  end;

implementation

uses
  System.IOUtils, System.Diagnostics;

constructor TCmdLineHandler.Create;
begin
  inherited;
  FOEMEncoding := TMBCSEncoding.Create(850);
  FParams := TStringList.Create();
end;

destructor TCmdLineHandler.Destroy;
begin
  FParams.Free;
  FOEMEncoding.Free;
  inherited Destroy;
end;

function TCmdLineHandler.ChangeChar(const Value: string; Source, Target: Char): string;
var
  I: Integer;
begin
  result := Value;
  for I := 1 to Length(result) do
    if result[I] = Source then
      result[I] := Target;
end;

function TCmdLineHandler.ChangePath(const FileName, Path: string): string;
begin
  Result := ChangeFilePath(FileName, Path);
end;

function TCmdLineHandler.CleanPathName(const Value: string): string;
begin
  result := ChangeChar(Value, TPath.AltDirectorySeparatorChar, TPath.DirectorySeparatorChar);
end;

class procedure TCmdLineHandler.Execute;
var
  instance: TCmdLineHandler;
begin
  instance := Self.Create;
  try
    if ParamCount = 0 then
      instance.ShowCmdLine
    else
      instance.HandleCmdLine;
  finally
    instance.Free;
  end;
end;

procedure TCmdLineHandler.LogLine(const Value: string);
begin
  if Logs <> nil then
    Logs.Add(Value);
  Writeln(Value);
end;

procedure TCmdLineHandler.SaveLogFile(const FileName: string);
begin
  if (FileName > '') and (Logs <> nil) and (Logs.Count > 0) then
    Logs.SaveToFile(FileName);
end;

function TCmdLineHandler.ExeName: string;
begin
  result := TPath.GetFileNameWithoutExtension(ParamStr(0));
end;

function TCmdLineHandler.ExePath: string;
begin
  result := TPath.GetDirectoryName(ParamStr(0));
end;

procedure TCmdLineHandler.FinishHandler;
begin
  SaveLogFile(LogFileName);
  FreeAndNil(FLogs);
end;

function TCmdLineHandler.GetFileEncoding(const AFileName: string; ADefaultEncoding: TEncoding): TEncoding;
const
  maxLengthPreamble = 3;
var
  buffer: TBytes;
  stream: TStream;
begin
  result := nil;
  SetLength(buffer, maxLengthPreamble);
  stream := TFileStream.Create(AFileName, fmOpenRead + fmShareDenyNone);
  try
    stream.ReadBuffer(buffer[0], Length(buffer));
  finally
    stream.Free;
  end;
  TEncoding.GetBufferEncoding(buffer, result, ADefaultEncoding);
end;

function TCmdLineHandler.GetSwitch(const Name: string): Boolean;
begin
  Result := FindCmdLineSwitch(Name);
end;

procedure TCmdLineHandler.HandleCmdLine;
var
  sw: TStopwatch;
begin
  sw := TStopwatch.StartNew;
  PrepareHandler;
  try
    InternalHandleCmdLine;
  finally
    FinishHandler;
  end;
  LogLine(Format('elapsed time: %d ms', [sw.ElapsedMilliseconds]));
end;

procedure TCmdLineHandler.LogError(const Value: string);
begin
  LogLine('Error: ' + Value);
  WaitForKeyPress;
end;

procedure TCmdLineHandler.PrepareHandler;
var
  S: string;
  I: Integer;
begin
  for I := 1 to ParamCount do begin
    S := ParamStr(I);
    if not CharInSet(S[1], SwitchChars) then
      Params.Add(S);
  end;

  if FindCmdLineSwitch('o', S) then
    S := TPath.GetFullPath(CleanPathName(S))
  else
    S := '';
  OutPath := S;

  if FindCmdLineSwitch('l', S) then
    S := CleanPathName(S)
  else
    S := '';
  LogFileName := S;
  if LogFileName > '' then
    FLogs := TStringList.Create;
end;

function TCmdLineHandler.SwitchValue(const Name: string; const Default: string): string;
begin
  if not FindCmdLineSwitch(Name, result) then
    Result := Default;
end;

class procedure TCmdLineHandler.WaitForKeyPress;
begin
  Writeln(SPressEnterToContinue);
  Readln;
end;

procedure TProgressHandler.DoProgress;
begin
  if Assigned(FOnProgress) then FOnProgress(Progress);
end;

class function TProgressHandler.ConsoleProgressEvent: TProgressEvent;
begin
  Result :=
    procedure(Percent: Integer)
    begin
      Write(Format('%.2d%%', [Percent]) + #8#8#8);
    end;
end;

procedure TProgressHandler.Finished;
begin
  Progress := 100;
end;

procedure TProgressHandler.LinkToConsole;
begin
  OnProgress := ConsoleProgressEvent();
end;

procedure TProgressHandler.Reset;
begin
  FCurrent := 0;
  FProgress := 0;
  DoProgress;
end;

procedure TProgressHandler.SetCount(const Value: Integer);
begin
  FCount := Value;
  Reset;
end;

procedure TProgressHandler.SetProgress(const Value: Integer);
begin
  if FProgress <> Value then begin
    FProgress := Value;
    DoProgress;
  end;
end;

procedure TProgressHandler.StepIt;
begin
  Inc(FCurrent);
  Progress := Round(100*FCurrent/FCount);
end;

end.
