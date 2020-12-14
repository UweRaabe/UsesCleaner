program UsesCleaner;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Masks,
  SimpleParser.Lexer.Types in 'SimpleParser.Lexer.Types.pas',
  SimpleParser.Lexer in 'SimpleParser.Lexer.pas',
  uCmdLineHandler in 'uCmdLineHandler.pas',
  uFileHandlerCmdLine in 'uFileHandlerCmdLine.pas',
  uSourceFileUsesClauseFormatter in 'uSourceFileUsesClauseFormatter.pas',
  UsesClause.Formatter in 'UsesClause.Formatter.pas',
  UsesClause.Types in 'UsesClause.Types.pas';

type
  TUsesCleaner = class(TFileHandlerCmdLine)
  private
    FIgnore: TStringList;
    FUsesManager: TSourceFileUsesClauseFormatter;
  protected
    procedure HandleFile(const SourceName, TargetName: string); override;
    procedure PrepareHandler; override;
    procedure FinishHandler; override;
    function IsIgnored(const AFileName: string): Boolean;
    procedure ShowCmdLine; override;
  public
    constructor Create; override;
    destructor Destroy; override;
  end;

constructor TUsesCleaner.Create;
begin
  inherited Create;
  FUsesManager := TSourceFileUsesClauseFormatter.Create();
  FIgnore := TStringList.Create();
end;

destructor TUsesCleaner.Destroy;
begin
  FIgnore.Free;
  FUsesManager.Free;
  inherited Destroy;
end;

procedure TUsesCleaner.FinishHandler;
var
  S: string;
begin
  if FUsesManager.CondInUses.Count > 0 then begin
    FUsesManager.CondInUses.SaveToFile('ConditionalUses.txt');
    Writeln('These files contain conditional uses clauses:');
    for S in  FUsesManager.CondInUses do
      Writeln(S);
  end;
  inherited;
end;

procedure TUsesCleaner.HandleFile(const SourceName, TargetName: string);
begin
  if IsIgnored(SourceName) then Exit;

  inherited;
  FUsesManager.FormatUsesClauses(SourceName, TargetName);
end;

function TUsesCleaner.IsIgnored(const AFileName: string): Boolean;
var
  S: string;
begin
  for S in FIgnore do begin
    if MatchesMask(AFileName, S) then
      Exit(True);
  end;
  Result := False;
end;

procedure TUsesCleaner.PrepareHandler;
begin
  inherited;
  FIgnore.CommaText := SwitchValue('ignore');
  FUsesManager.LoadConfigFile(SwitchValue('c', TPath.ChangeExtension(ExeName, '.cfg')));
end;

procedure TUsesCleaner.ShowCmdLine;
begin
  Writeln(SUsage, ': ', ExeName, ' [<filepath>]<filename> [-c:<configfile>] [-o:<outputpath>] [-l:<logfile>] [-s]');
  Writeln('       <filename> ', SMayContainWildcards);
  Writeln('       <configfile> default is ', TPath.ChangeExtension(ExeName, '.cfg'));
  Writeln('       <outputpath> if not specified, original files will be changed!');
  Writeln('       -s: also handles subfolders ');
  Writeln;
end;

begin
  try
    TUsesCleaner.Execute;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
  {$IFDEF DEBUG}
  TUsesCleaner.WaitForKeyPress;
  {$ENDIF}
end.
