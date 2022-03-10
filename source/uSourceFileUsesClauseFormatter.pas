unit uSourceFileUsesClauseFormatter;

interface

uses
  System.Classes, System.Generics.Collections,
  UsesClause.Types, UsesClause.Formatter;

type
  TSourceFileUsesClauseFormatter = class
  private
    FCondInUses: TStrings;
    FFileContent: string;
    FUsesHelper: TUsesClauseFormatter;
    FImplInfo: TUsesInfo;
    FIntfInfo: TUsesInfo;
    procedure BuildUsesList;
    function GetCompDirectInImplementation: Boolean;
    function GetCompDirectInInterface: Boolean;
    function GetScopeAliases: string;
    procedure InitSettings;
    procedure WriteInterfaceUses(Source: TStrings);
    function WriteUses(Source: TStrings; var UsesInfo: TUsesInfo): Integer;
    procedure WriteImplementationUses(Source: TStrings);
  public
    constructor Create;
    destructor Destroy; override;
    procedure FormatUsesClauses; overload;
    procedure FormatUsesClauses(const FileName: string); overload;
    procedure FormatUsesClauses(const SourceName, TargetName: string); overload;
    procedure LoadConfigFile(const FileName: string);
    procedure LoadFromFile(const FileName: string);
    procedure SaveToFile(const FileName: string);
    property CompDirectInImplementation: Boolean read GetCompDirectInImplementation;
    property CompDirectInInterface: Boolean read GetCompDirectInInterface;
    property CondInUses: TStrings read FCondInUses;
    property ScopeAliases: string read GetScopeAliases;
    property UsesHelper: TUsesClauseFormatter read FUsesHelper;
  end;

implementation

uses
  System.SysUtils, System.StrUtils, System.Types, System.IOUtils, System.IniFiles;

constructor TSourceFileUsesClauseFormatter.Create;
begin
  inherited Create;
  FCondInUses := TStringList.Create;
  FUsesHelper := TUsesClauseFormatter.Create();
  FIntfInfo := TUsesInfo.Create();
  FImplInfo := TUsesInfo.Create();
  InitSettings;
end;

destructor TSourceFileUsesClauseFormatter.Destroy;
begin
  FImplInfo.Free;
  FIntfInfo.Free;
  FCondInUses.Free;
  FUsesHelper.Free;
  inherited Destroy;
end;

procedure TSourceFileUsesClauseFormatter.BuildUsesList;
var
  reader: TUsesInfoReader;
begin
  reader := TUsesInfoReader.Create;
  try
    reader.IntfUses := FIntfInfo;
    reader.ImplUses := FImplInfo;
    reader.LoadSource(FFileContent);
  finally
    reader.Free;
  end;
end;

procedure TSourceFileUsesClauseFormatter.FormatUsesClauses;
var
  lst: TStringList;
begin
  lst := TStringList.Create;
  try
    if FImplInfo.Exists then begin
      UsesHelper.Execute(FImplInfo, lst);
      WriteImplementationUses(lst);
    end;
    if FIntfInfo.Exists then begin
      UsesHelper.Execute(FIntfInfo, lst);
      WriteInterfaceUses(lst);
    end;
  finally
    lst.Free;
  end;
end;

procedure TSourceFileUsesClauseFormatter.FormatUsesClauses(const FileName: string);
begin
  FormatUsesClauses(FileName, FileName);
end;

procedure TSourceFileUsesClauseFormatter.FormatUsesClauses(const SourceName, TargetName: string);
var
  saveCompressed: Boolean;
  saveGroupNames: string;
begin
  saveCompressed := UsesHelper.Compressed;
  saveGroupNames := UsesHelper.GroupNames;
  try
    if MatchText(TPath.GetExtension(SourceName), ['.dpr', '.dpk']) then begin
      UsesHelper.Compressed := False;
      UsesHelper.GroupNames := '';
    end;
    LoadFromFile(SourceName);
    FormatUsesClauses;
    SaveToFile(TargetName);
  finally
    UsesHelper.Compressed := saveCompressed;
    UsesHelper.GroupNames := saveGroupNames;
  end;
end;

function TSourceFileUsesClauseFormatter.GetCompDirectInImplementation: Boolean;
begin
  Result := FImplInfo.HasCompilerDirective;
end;

function TSourceFileUsesClauseFormatter.GetCompDirectInInterface: Boolean;
begin
  Result := FIntfInfo.HasCompilerDirective;
end;

function TSourceFileUsesClauseFormatter.GetScopeAliases: string;
begin
  Result := UsesHelper.ScopeAliases;
end;

procedure TSourceFileUsesClauseFormatter.InitSettings;
begin
  UsesHelper.UnitAliases := 'WinTypes=Winapi.Windows;WinProcs=Winapi.Windows;DbiTypes=BDE;DbiProcs=BDE;DbiErrs=BDE;';
  UsesHelper.UnitScopeNames := 'Winapi;System.Win;Data.Win;Datasnap.Win;Web.Win;Soap.Win;Xml.Win;Bde;System;Xml;Data;Datasnap;Web;Soap;Vcl;Vcl.Imaging;Vcl.Touch;Vcl.Samples;Vcl.Shell';
  UsesHelper.SearchPath := 'c:\Program Files (x86)\Embarcadero\Studio\19.0\lib\win32\release';
  UsesHelper.GroupNames := '<UnitScopeNames>';
end;

procedure TSourceFileUsesClauseFormatter.LoadConfigFile(const FileName: string);
var
  ini: TMemInifile;
begin
  if FileName = '' then Exit;
  if not TFile.Exists(FileName) then Exit;

  ini := TMemInifile.Create(FileName);
  try
    UsesHelper.Indentation := ini.ReadInteger('Settings', 'Indentation', UsesHelper.Indentation);
    UsesHelper.Compressed := ini.ReadBool('Settings', 'Compressed', UsesHelper.Compressed);
    UsesHelper.MaxLineLength := ini.ReadInteger('Settings', 'MaxLineLength', UsesHelper.MaxLineLength);
    UsesHelper.SearchPath := ini.ReadString('Settings', 'SearchPath', UsesHelper.SearchPath);
    UsesHelper.UnitAliases := ini.ReadString('Settings', 'UnitAliases', UsesHelper.UnitAliases);
    UsesHelper.UnitScopeNames := ini.ReadString('Settings', 'UnitScopeNames', UsesHelper.UnitScopeNames);
    UsesHelper.GroupNames := ini.ReadString('Settings', 'GroupNames', UsesHelper.GroupNames);
    Ini.ReadSectionValues('Groups', UsesHelper.Groups);
  finally
    ini.Free;
  end;
end;

procedure TSourceFileUsesClauseFormatter.LoadFromFile(const FileName: string);
begin
  FFileContent := TFile.ReadAllText(FileName);
  BuildUsesList;
  if CompDirectInImplementation or CompDirectInInterface then begin
    CondInUses.Add(FileName);
  end;
end;

procedure TSourceFileUsesClauseFormatter.SaveToFile(const FileName: string);
begin
  TFile.WriteAllText(FileName, FFileContent, TEncoding.ANSI);
end;

procedure TSourceFileUsesClauseFormatter.WriteInterfaceUses(Source: TStrings);
var
  diff: Integer;
begin
  diff := WriteUses(Source, FIntfInfo);
  FImplInfo.MoveLines(diff);
end;

function TSourceFileUsesClauseFormatter.WriteUses(Source: TStrings; var UsesInfo: TUsesInfo): Integer;
var
  count: Integer;
  S: string;
begin
  result := 0;
  if UsesInfo.BegOfUses < UsesInfo.EndOfUses then begin
    S := Source.Text.TrimRight([#13,#10,' ']);
    count := UsesInfo.EndOfUses - UsesInfo.BegOfUses;
    FFileContent := FFileContent.Remove(UsesInfo.BegOfUses, count);
    FFileContent := FFileContent.Insert(UsesInfo.BegOfUses, S);
    result := S.Length - Count;
    UsesInfo.EndOfUses := UsesInfo.EndOfUses + result;
  end;
end;

procedure TSourceFileUsesClauseFormatter.WriteImplementationUses(Source: TStrings);
begin
  WriteUses(Source, FImplInfo);
end;

end.
