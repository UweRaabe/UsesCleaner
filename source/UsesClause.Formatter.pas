unit UsesClause.Formatter;

interface

uses
  System.Classes, UsesClause.Types;

const
  cRefUnitScopeNames = '<UnitScopeNames>';

type
  IGroupNameMatcher = interface
  ['{6D7C4F30-F2B2-4FF6-9448-678138B82A24}']
    function Matches(const AUnitName: string): Boolean;
  end;

type
  TUsesClauseFormatter = class
  private
    FCompressed: Boolean;
    FEncodingName: string;
    FIndentation: Integer;
    FMaxLineLength: Integer;
    FFoundUnits: TStringList;
    FGroupNames: TStringList;
    FGroups: TStringList;
    FHasComments: Boolean;
    FScopeAliases: TStringList;
    FSearchPath: TStringList;
    FUnitAliases: TStringList;
    FUnitScopeNames: TStringList;
    procedure AddStringsReverse(Source, Target: TStrings); overload;
    procedure AddStringsReverse(Source, Target: TUsesList); overload;
    function CreateDelimitedStrings: TStringList;
    function CreateDelimitedSortedStrings: TStringList;
    function CreateMatcher(const AGroupName: string): IGroupNameMatcher;
    function CreateSortedStrings: TStringList;
    function FindBestGroup(const UnitName: string; GroupNames: TStrings; StartIdx: Integer = 0): string; overload;
    procedure FindUnits(Path, UnitName: string);
    function GetGroupNames: string;
    function GetScopeAliases: string;
    function GetSearchPath: string;
    function GetUnitAliases: string;
    function GetUnitScopeNames: string;
    procedure InternalGroupUnitNames(SourceReversed, Target, GroupNames: TStrings); overload;
    procedure InternalGroupUnitNames(SourceReversed, Target: TUsesList; GroupNames: TStrings); overload;
    procedure InternalGroupUnitNames(SourceReversed, Target: TUsesList; const GroupName: string); overload;
    function IsUnitInSearchPath(var UnitName: string): Boolean;
    procedure RemoveDoubles(UsesList: TUsesList);
    procedure SetGroupNames(const Value: string);
    procedure SetScopeAliases(const Value: string);
    procedure SetSearchPath(const Value: string);
    procedure SetUnitAliases(const Value: string);
    procedure SetUnitScopeNames(const Value: string);
    procedure UpdateSearchPathes;
  protected
    function IsComment(const Value: string): Boolean;
    function IsDirective(const Value: string): Boolean;
    property FoundUnits: TStringList read FFoundUnits;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddSearchPath(const APath: string);
    procedure CompressUses(UsesList: TUsesList; Target: TStrings);
    procedure Execute(UsesInfo: TUsesInfo; Target: TStrings);
    procedure ExpandUnitScopeNames(UsesList: TUsesList);
    function FindBestGroup(const UnitName: string): string; overload;
    procedure GroupUnitNames(UnitNames: TStrings); overload;
    procedure GroupUnitNames(UsesList: TUsesList); overload;
    procedure GroupUnitNames(UsesList: TUsesList; StartIndex, Count: Integer); overload;
    procedure RemoveUnitScopeNames(UnitNames: TStrings);
    procedure ResolveAliases(UsesList: TUsesList);
    property Compressed: Boolean read FCompressed write FCompressed;
    property EncodingName: string read FEncodingName write FEncodingName;
    property GroupNames: string read GetGroupNames write SetGroupNames;
    property Groups: TStringList read FGroups;
    property Indentation: Integer read FIndentation write FIndentation;
    property MaxLineLength: Integer read FMaxLineLength write FMaxLineLength;
    property ScopeAliases: string read GetScopeAliases write SetScopeAliases;
    property SearchPath: string read GetSearchPath write SetSearchPath;
    property UnitAliases: string read GetUnitAliases write SetUnitAliases;
    property UnitScopeNames: string read GetUnitScopeNames write SetUnitScopeNames;
  end;

implementation

uses
  System.SysUtils, System.StrUtils, System.Masks;

type
  TUsesInfoHandler = class(TUsesInfoVisitor)

  private
    FFormatter: TUsesClauseFormatter;
  public
    constructor Create(AFormatter: TUsesClauseFormatter);
    procedure Execute(UsesList: TUsesList);
    procedure Finish; virtual;
    procedure Prepare; virtual;
    property Formatter: TUsesClauseFormatter read FFormatter;
  end;

type
  TUsesListGrouper = class(TUsesInfoHandler)
  private
    FList: TStringList;
  protected
    procedure VisitDirective(const Value: string); override;
    procedure VisitUnitName(var Value: string; Mode: TClosingMode); override;
  public
    constructor Create(AFormatter: TUsesClauseFormatter);
    destructor Destroy; override;
    procedure Finish; override;
  end;

type
  TUsesInfoWriterClass = class of TUsesInfoWriter;
  TUsesInfoWriter = class(TUsesInfoHandler)
  private
    FIndent: string;
    FTarget: TStrings;
  protected
  const
    cEndChar: array[TClosingMode] of string = (',', ';', '');
    property Indent: string read FIndent;
  public
    constructor Create(AFormatter: TUsesClauseFormatter; ATarget: TStrings);
    procedure Prepare; override;
    property Target: TStrings read FTarget;
  end;

  TCompressedWriter = class(TUsesInfoWriter)
  private
    FGroup: string;
    FLine: string;
    FMaxLen: Integer;
    function CheckGroup(const Value: string): Boolean;
    procedure FlushLine;
  protected
    procedure VisitDirective(const Value: string); override;
    procedure VisitUnitName(var Value: string; Mode: TClosingMode); override;
  public
    procedure Finish; override;
    procedure Prepare; override;
  end;

  TFlatWriter = class(TUsesInfoWriter)
  protected
    procedure VisitDirective(const Value: string); override;
    procedure VisitUnitName(var Value: string; Mode: TClosingMode); override;
  end;

  TFlixWriter = class(TUsesInfoWriter)
  private
    FGroup: string;
    FLastMode: TClosingMode;
    function CheckGroup(const Value: string): Boolean;
  protected
    procedure VisitDirective(const Value: string); override;
    procedure VisitUnitName(var Value: string; Mode: TClosingMode); override;
  public
    procedure Prepare; override;
  end;

type
  TGroupNameMatcher = class(TInterfacedObject, IGroupNameMatcher)
  private
    FGroupName: string;
  public
    constructor Create(const AGroupName: string);
    function Matches(const AUnitName: string): Boolean; virtual; abstract;
    property GroupName: string read FGroupName;
  end;

type
  TListGroupNameMatcher = class(TGroupNameMatcher)
  private
    FList: TStringList;
  protected
    property List: TStringList read FList;
  public
    constructor Create(const AGroupName, AGroups: string);
    destructor Destroy; override;
    function Matches(const AUnitName: string): Boolean; override;
  end;

type
  TSimpleListGroupNameMatcher = class(TListGroupNameMatcher)
  public
    constructor Create(const AGroupName: string);
  end;

type
  TMaskGroupNameMatcher = class(TGroupNameMatcher)
  private
    FMask: TMask;
  protected
    property Mask: TMask read FMask;
  public
    constructor Create(const AGroupName: string);
    destructor Destroy; override;
    function Matches(const AUnitName: string): Boolean; override;
  end;

type
  TSimpleGroupNameMatcher = class(TGroupNameMatcher)
  public
    function Matches(const AUnitName: string): Boolean; override;
  end;

constructor TUsesClauseFormatter.Create;
begin
  inherited Create;
  FFoundUnits := CreateSortedStrings;
  FUnitScopeNames := CreateDelimitedStrings;
  FUnitAliases := CreateDelimitedStrings;
  FGroupNames := CreateDelimitedStrings;
  FSearchPath := CreateDelimitedStrings;
  FScopeAliases := CreateDelimitedSortedStrings;
  FGroups := TStringList.Create();

  FIndentation := 2;
  FMaxLineLength := 80;
//  FCompressed := true;
end;

destructor TUsesClauseFormatter.Destroy;
begin
  FGroups.Free;
  FScopeAliases.Free;
  FSearchPath.Free;
  FGroupNames.Free;
  FUnitAliases.Free;
  FUnitScopeNames.Free;
  FFoundUnits.Free;
  inherited Destroy;
end;

procedure TUsesClauseFormatter.AddSearchPath(const APath: string);
begin
  FindUnits(APath, '*.pas');
  FindUnits(APath, '*.dcu');
end;

procedure TUsesClauseFormatter.AddStringsReverse(Source, Target: TStrings);
var
  I: Integer;
begin
  for I := Source.Count - 1 downto 0 do begin
    Target.Add(Source[I]);
  end;
end;

procedure TUsesClauseFormatter.AddStringsReverse(Source, Target: TUsesList);
var
  I: Integer;
begin
  Target.DirectiveBegin := Source.DirectiveBegin;
  Target.DirectiveEnd := Source.DirectiveEnd;
  for I := Source.Count - 1 downto 0 do begin
    if Source.IsSubList(I) then begin
      AddStringsReverse(Source.SubList[I], Target.CreateSubList(''));
    end
    else begin
      Target.AddUnitName(Source[I]);
    end;
  end;
end;

procedure TUsesClauseFormatter.CompressUses(UsesList: TUsesList; Target: TStrings);
var
  cls: TUsesInfoWriterClass;
  vis: TUsesInfoWriter;
begin
  Target.Clear;
  if UsesList.Count = 0 then Exit;
  if Compressed then
    cls := TCompressedWriter
  else
    cls := TFlixWriter;
  vis := cls.Create(Self, Target);
  try
    vis.Execute(UsesList);
  finally
    vis.Free;
  end;
end;

function TUsesClauseFormatter.CreateDelimitedStrings: TStringList;
begin
  Result := TStringList.Create;
  Result.QuoteChar := '"';
  Result.Delimiter := ';';
  Result.StrictDelimiter := True;
end;

function TUsesClauseFormatter.CreateDelimitedSortedStrings: TStringList;
begin
  Result := CreateDelimitedStrings;
  Result.Duplicates := dupIgnore;
  Result.Sorted := true;
  Result.CaseSensitive := false;
end;

function TUsesClauseFormatter.CreateMatcher(const AGroupName: string): IGroupNameMatcher;
begin
  if AGroupName.StartsWith('@') then
    Result := TListGroupNameMatcher.Create(AGroupName, Groups.Values[AGroupName.Substring(1)])
  else if AGroupName.StartsWith('(') and AGroupName.EndsWith(')') then
    Result := TSimpleListGroupNameMatcher.Create(AGroupName)
  else if AGroupName.IndexOfAny(['*', '?', '[']) >= 0 then
    Result := TMaskGroupNameMatcher.Create(AGroupName)
  else
    Result := TSimpleGroupNameMatcher.Create(AGroupName);
end;

function TUsesClauseFormatter.CreateSortedStrings: TStringList;
begin
  Result := TStringList.Create;
end;

procedure TUsesClauseFormatter.Execute(UsesInfo: TUsesInfo; Target: TStrings);
begin
  FHasComments := False;
  ResolveAliases(UsesInfo.UsesList);
  ExpandUnitScopeNames(UsesInfo.UsesList);
  GroupUnitNames(UsesInfo.UsesList);
  CompressUses(UsesInfo.UsesList, Target);
end;

procedure TUsesClauseFormatter.ExpandUnitScopeNames(UsesList: TUsesList);
{ Expands UsesList with UnitScopeNames.
  The first unit scope name that results in a unit found in the search path is prefixed to the unit name. }
var
  I: Integer;
  J: Integer;
  newUnitName: string;
  unitName: string;
begin
  if FUnitScopeNames.Count = 0 then Exit;

  for I := 0 to UsesList.Count - 1 do begin
    if UsesList.IsSubList(I) then begin
      ExpandUnitScopeNames(UsesList.SubList[I]);
    end
    else begin
      unitName := UsesList[I];
      newUnitName := unitName;
      if IsUnitInSearchPath(newUnitName) then begin
        UsesList[I] := newUnitName;
        Continue;
      end;
      for J := 0 to FUnitScopeNames.Count - 1 do begin
        newUnitName := FUnitScopeNames[J] + '.' + unitName;
        if IsUnitInSearchPath(newUnitName) then begin
          UsesList[I] := newUnitName;
          FScopeAliases.AddPair(newUnitName, unitName);
          Break;
        end;
      end;
    end;
  end;
  RemoveDoubles(UsesList);
end;

function TUsesClauseFormatter.FindBestGroup(const UnitName: string; GroupNames: TStrings; StartIdx: Integer = 0): string;
var
  groupName: string;
  I: Integer;
  matcher: IGroupNameMatcher;
begin
  result := '';
  for I := StartIdx to GroupNames.Count - 1 do begin
    groupName := GroupNames[I];
    if SameText(groupName, cRefUnitScopeNames) then begin
      result := FindBestGroup(UnitName, FUnitScopeNames);
    end
    else begin
      matcher := CreateMatcher(groupName);
      if matcher.Matches(UnitName) then begin
        if (Length(result) < Length(groupName)) then begin
          result := groupName;
        end;
      end;
    end;
  end;
end;

function TUsesClauseFormatter.FindBestGroup(const UnitName: string): string;
begin
  result := FindBestGroup(UnitName, FGroupNames);
end;

procedure TUsesClauseFormatter.FindUnits(Path, UnitName: string);
var
  SR: TSearchRec;
begin
  if FindFirst(IncludeTrailingPathDelimiter(Path) + UnitName, faAnyFile, SR) = 0 then begin
    try
      repeat
        if (SR.Attr and faDirectory = 0) then begin
          FFoundUnits.Add(ChangeFileExt(SR.Name, ''));
        end;
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
  end;
end;

function TUsesClauseFormatter.GetGroupNames: string;
begin
  Result := FGroupNames.DelimitedText;
end;

function TUsesClauseFormatter.GetScopeAliases: string;
begin
  Result := FScopeAliases.DelimitedText;
end;

function TUsesClauseFormatter.GetSearchPath: string;
begin
  Result := FSearchPath.DelimitedText;
end;

function TUsesClauseFormatter.GetUnitAliases: string;
begin
  Result := FUnitAliases.DelimitedText;
end;

function TUsesClauseFormatter.GetUnitScopeNames: string;
begin
  Result := FUnitScopeNames.DelimitedText;
end;

procedure TUsesClauseFormatter.GroupUnitNames(UnitNames: TStrings);
{ Sorts UnitNames by GroupNames.
  Units starting with the same group name are grouped together while their relative order remains the same.
  The overall sorting is done by the order of GroupNames. Units not matching any group name are appended in their
  original order. }
var
  unitNamesReversed: TStringList;
begin
  if FGroupNames.Count = 0 then Exit;

  unitNamesReversed := TStringList.Create;
  try
    { building the list in reverse order simplifies the deleting inside the inner loop }
    AddStringsReverse(UnitNames, unitNamesReversed);
    UnitNames.BeginUpdate;
    try
      UnitNames.Clear;
      InternalGroupUnitNames(unitNamesReversed, UnitNames, FGroupNames);
      { append all remaining units }
      AddStringsReverse(unitNamesReversed, UnitNames);
    finally
      UnitNames.EndUpdate;
    end;
  finally
    unitNamesReversed.Free;
  end;
end;

procedure TUsesClauseFormatter.GroupUnitNames(UsesList: TUsesList);
{ Sorts UsesList by GroupNames.
  Units starting with the same group name are grouped together while their relative order remains the same.
  The overall sorting is done by the order of GroupNames. Units not matching any group name are appended in their
  original order. }
var
  cnt: Integer;
  I: Integer;
  idx: Integer;
begin
  if FGroupNames.Count = 0 then Exit;

  idx := 0;
  cnt := 0;
  for I := 0 to UsesList.Count - 1 do begin
    if UsesList.IsSubList(I) then begin
      if cnt > 0 then begin
        GroupUnitNames(UsesList, idx, cnt);
        cnt := 0;
      end;
      GroupUnitNames(UsesList.SubList[I]);
    end
    else begin
      if cnt = 0 then begin
        idx := I;
      end;
      Inc(cnt);
    end;
  end;
  if cnt > 0 then begin
    GroupUnitNames(UsesList, idx, cnt);
  end;
end;

procedure TUsesClauseFormatter.GroupUnitNames(UsesList: TUsesList; StartIndex, Count: Integer);
{ Sorts UsesList by GroupNames.
  Units starting with the same group name are grouped together while their relative order remains the same.
  The overall sorting is done by the order of GroupNames. Units not matching any group name are appended in their
  original order. }
var
  list: TStringList;
  I: Integer;
begin
  if FGroupNames.Count = 0 then Exit;

  list := TStringList.Create;
  try
    for I := 0 to Count - 1 do begin
      list.Add(UsesList[StartIndex + I]);
    end;
    GroupUnitNames(list);
    for I := 0 to Count - 1 do begin
      UsesList[StartIndex + I] := list[I];
    end;
  finally
    list.Free;
  end;
end;

procedure TUsesClauseFormatter.InternalGroupUnitNames(SourceReversed, Target, GroupNames: TStrings);
var
  groupName: string;
  I: Integer;
  J: Integer;
  matcher: IGroupNameMatcher;
begin
  for J := 0 to GroupNames.Count - 1 do begin
    groupName := GroupNames[J];
    if SameText(groupName, cRefUnitScopeNames) then begin
      InternalGroupUnitNames(SourceReversed, Target, FUnitScopeNames);
    end
    else begin
      matcher := CreateMatcher(groupName);
      for I := SourceReversed.Count - 1 downto 0 do begin
        if matcher.Matches(SourceReversed[I]) then begin
          if FindBestGroup(SourceReversed[I], GroupNames, J) = groupName then begin
            Target.Add(SourceReversed[I]);
            SourceReversed.Delete(I);
          end;
        end;
      end;
    end;
  end;
end;

procedure TUsesClauseFormatter.InternalGroupUnitNames(SourceReversed, Target: TUsesList; GroupNames: TStrings);
var
  J: Integer;
begin
  for J := 0 to GroupNames.Count - 1 do begin
    InternalGroupUnitNames(SourceReversed, Target, GroupNames[J]);
  end;
end;

procedure TUsesClauseFormatter.InternalGroupUnitNames(SourceReversed, Target: TUsesList; const GroupName: string);
var
  I: Integer;
  S: string;
begin
  if SameText(GroupName, cRefUnitScopeNames) then begin
    InternalGroupUnitNames(SourceReversed, Target, FUnitScopeNames);
  end
  else begin
    S := GroupName + '.';
    for I := SourceReversed.Count - 1 downto 0 do begin
      if SourceReversed.IsSubList(I) then Continue;
      if SameText(S, LeftStr(SourceReversed[I], Length(S))) then begin
        Target.AddUnitName(SourceReversed[I]);
        SourceReversed.Delete(I);
      end;
    end;
  end;
end;

function TUsesClauseFormatter.IsComment(const Value: string): Boolean;
begin
  Result := Value.StartsWith('{') or Value.StartsWith('//');
end;

function TUsesClauseFormatter.IsDirective(const Value: string): Boolean;
begin
  Result := Value.StartsWith('{$');
end;

function TUsesClauseFormatter.IsUnitInSearchPath(var UnitName: string): Boolean;
var
  idx: Integer;
begin
  idx := FFoundUnits.IndexOf(UnitName);
  Result := (idx >= 0);
  if Result then begin
    UnitName := FFoundUnits[idx];
  end;
end;

procedure TUsesClauseFormatter.RemoveDoubles(UsesList: TUsesList);
var
  lst: TStringList;
  I: Integer;
  idx: Integer;
  S: string;
begin
  lst := CreateSortedStrings;
  try
    I := 0;
    while I < UsesList.Count do begin
      if UsesList.IsSubList(I) then begin
        Inc(I);
      end
      else begin
        S := UsesList[I];
        if lst.Find(S, idx) then begin
          UsesList.Delete(I);
        end
        else begin
          lst.Add(S);
          Inc(I);
        end;
      end;
    end;
  finally
    lst.Free;
  end;
end;

procedure TUsesClauseFormatter.RemoveUnitScopeNames(UnitNames: TStrings);
{ Removes UnitScopeNames from UnitNames.
  The longest unit scope name found is removed from the unit name. }
var
  bestScope: string;
  I: Integer;
  unitName: string;
begin
  for I := 0 to UnitNames.Count - 1 do begin
    unitName := UnitNames[I];
    bestScope := FindBestGroup(unitName, FUnitScopeNames);
    if bestScope > '' then begin
      Delete(unitName, 1, Length(bestScope) + 1);
      UnitNames[I] := unitName;
    end;
  end;
end;

procedure TUsesClauseFormatter.ResolveAliases(UsesList: TUsesList);
var
  I: Integer;
  idx: Integer;
begin
  if FUnitAliases.Count = 0 then Exit;

  for I := 0 to UsesList.Count - 1 do begin
    if UsesList.IsSubList(I) then begin
      FHasComments := True;
      ResolveAliases(UsesList.SubList[I]);
    end
    else begin
      idx := FUnitAliases.IndexOfName(UsesList[I]);
      if idx >= 0 then begin
        UsesList[I] := FUnitAliases.ValueFromIndex[idx];
      end;
    end;
  end;
  RemoveDoubles(UsesList);
end;

procedure TUsesClauseFormatter.SetGroupNames(const Value: string);
begin
  FGroupNames.DelimitedText := Value;
end;

procedure TUsesClauseFormatter.SetScopeAliases(const Value: string);
begin
  FScopeAliases.DelimitedText := Value;
end;

procedure TUsesClauseFormatter.SetSearchPath(const Value: string);
begin
  FSearchPath.DelimitedText := Value;
  UpdateSearchPathes;
end;

procedure TUsesClauseFormatter.SetUnitAliases(const Value: string);
begin
  FUnitAliases.DelimitedText := Value;
end;

procedure TUsesClauseFormatter.SetUnitScopeNames(const Value: string);
begin
  FUnitScopeNames.DelimitedText := Value;
end;

procedure TUsesClauseFormatter.UpdateSearchPathes;
var
  I: Integer;
begin
  FFoundUnits.Clear;
  for I := 0 to FSearchPath.Count - 1 do begin
    AddSearchPath(FSearchPath[I]);
  end;
end;

function TCompressedWriter.CheckGroup(const Value: string): Boolean;
begin
  Result := (FGroup = '*') or SameText(FGroup, Value);
end;

procedure TCompressedWriter.Finish;
begin
  FlushLine;
  inherited;
end;

procedure TCompressedWriter.FlushLine;
begin
  if FLine > '' then begin
    Target.Add(indent + FLine);
  end;
  FLine := '';
end;

procedure TCompressedWriter.Prepare;
begin
  inherited;
  FMaxLen := Formatter.MaxLineLength - Formatter.Indentation;
  FLine := '';
  FGroup := '*';
end;

procedure TCompressedWriter.VisitDirective(const Value: string);
begin
  if Value > '' then begin
    FlushLine;
    FGroup := '*';
    Target.Add(Indent + Value);
  end;
end;

procedure TCompressedWriter.VisitUnitName(var Value: string; Mode: TClosingMode);
var
  groupChanged: Boolean;
  newGroup: string;
  newLine: string;
  S: string;
begin
  newLine := FLine;
  if newLine > '' then begin
    newLine := newLine + ' ';
  end;
  S := Value + cEndChar[Mode];
  newLine := newLine + S;
  newGroup := Formatter.FindBestGroup(Value);
  groupChanged := not CheckGroup(newGroup);
  if (Length(newLine) > FMaxLen) or groupChanged then begin
    FlushLine;
    newLine := S;
  end;
//  if (groupChanged or (FGroup = '*')) and newGroup.StartsWith('@') then begin
//    newLine := '{' + newGroup.Substring(1) + '} ' + newLine;
//  end;
  FLine := newLine;
  FGroup := newGroup;
end;

constructor TUsesInfoWriter.Create(AFormatter: TUsesClauseFormatter; ATarget: TStrings);
begin
  inherited Create(AFormatter);
  FTarget := ATarget;
end;

procedure TUsesInfoWriter.Prepare;
begin
  inherited;
  FIndent := StringOfChar(' ', Formatter.Indentation);
  Target.Add('uses');
end;

procedure TFlatWriter.VisitDirective(const Value: string);
begin
  if Value > '' then
    Target.Add(Indent + Value);
end;

procedure TFlatWriter.VisitUnitName(var Value: string; Mode: TClosingMode);
begin
  Target.Add(Indent + Value + cEndChar[Mode]);
end;

constructor TUsesListGrouper.Create(AFormatter: TUsesClauseFormatter);
begin
  inherited;
  FList := TStringList.Create();
end;

destructor TUsesListGrouper.Destroy;
begin
  FList.Free;
  inherited Destroy;
end;

procedure TUsesListGrouper.Finish;
begin

end;

procedure TUsesListGrouper.VisitDirective(const Value: string);
begin

end;

procedure TUsesListGrouper.VisitUnitName(var Value: string; Mode: TClosingMode);
begin
  FList.Add(Value);
end;

constructor TUsesInfoHandler.Create(AFormatter: TUsesClauseFormatter);
begin
  inherited Create;
  FFormatter := AFormatter;
end;

procedure TUsesInfoHandler.Execute(UsesList: TUsesList);
begin
  Prepare;
  VisitList(UsesList);
  Finish;
end;

procedure TUsesInfoHandler.Finish;
begin
end;

procedure TUsesInfoHandler.Prepare;
begin
end;

constructor TGroupNameMatcher.Create(const AGroupName: string);
begin
  inherited Create;
  FGroupName := AGroupName;
end;

constructor TSimpleListGroupNameMatcher.Create(const AGroupName: string);
begin
  inherited Create(AGroupName, AGroupName.Substring(1, AGroupName.Length - 2));
end;

constructor TMaskGroupNameMatcher.Create(const AGroupName: string);
begin
  inherited Create(AGroupName);
  FMask := TMask.Create(GroupName);
end;

destructor TMaskGroupNameMatcher.Destroy;
begin
  FMask.Free;
  inherited Destroy;
end;

function TMaskGroupNameMatcher.Matches(const AUnitName: string): Boolean;
begin
  Result := Mask.Matches(AUnitName);
end;

function TSimpleGroupNameMatcher.Matches(const AUnitName: string): Boolean;
begin
  Result := SameText(GroupName, AUnitName) or AUnitName.StartsWith(GroupName + '.', True);
end;

constructor TListGroupNameMatcher.Create(const AGroupName, AGroups: string);
begin
  inherited Create(AGroupName);
  FList := TStringList.Create;
  FList.CommaText := AGroups;
  FList.Sorted := True;
end;

destructor TListGroupNameMatcher.Destroy;
begin
  FList.Free;
  inherited Destroy;
end;

function TListGroupNameMatcher.Matches(const AUnitName: string): Boolean;
var
  idx: Integer;
begin
  Result := List.Find(AUnitName, idx);
end;

function TFlixWriter.CheckGroup(const Value: string): Boolean;
begin
  Result := (FGroup = '*') or SameText(FGroup, Value);
end;

procedure TFlixWriter.Prepare;
begin
  inherited;
  FGroup := '*';
  FLastMode := cmNone;
end;

procedure TFlixWriter.VisitDirective(const Value: string);
begin
  if Value > '' then begin
    FGroup := '*';
    Target.Add(Indent + Value);
  end;
end;

procedure TFlixWriter.VisitUnitName(var Value: string; Mode: TClosingMode);
var
  newGroup: string;
begin
  newGroup := Formatter.FindBestGroup(Value);
  if not CheckGroup(newGroup) then begin
    Target.Add('');
  end;
  Target.Add(Indent + Format('%-2s', [cEndChar[FLastMode]]) + Value);
  if Mode = cmLast then begin
    Target.Add('');
    Target.Add(Indent + cEndChar[Mode]);
  end;
  FLastMode := Mode;
  FGroup := newGroup;
end;

end.
