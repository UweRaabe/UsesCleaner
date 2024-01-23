unit UsesClause.Types;

interface

uses
  System.Classes;

type
  TUnitSection = (sImplementation, sInterface);
  TClosingMode = (cmNormal, cmLast, cmNone);

type
  TUsesList = class
  private
    FData: TStringList;
    FDirectiveBegin: string;
    FDirectiveEnd: string;
    FElseList: TUsesList;
    FParent: TUsesList;
    function GetCount: Integer;
    function GetItems(Index: Integer): string;
    function GetSubList(Index: Integer): TUsesList;
    procedure SetItems(Index: Integer; const Value: string);
  public
    constructor Create(AParent: TUsesList);
    destructor Destroy; override;
    procedure AddUnitName(const Value: string);
    procedure Clear;
    function CreateSubList(const Value: string): TUsesList;
    function CreateElseList(const Value: string): TUsesList;
    procedure Delete(Index: Integer);
    procedure ExtendLastUnitName(const Value: string);
    function IsSubList(Index: Integer): Boolean;
    property Count: Integer read GetCount;
    property Data: TStringList read FData;
    property DirectiveBegin: string read FDirectiveBegin write FDirectiveBegin;
    property DirectiveEnd: string read FDirectiveEnd write FDirectiveEnd;
    property Parent: TUsesList read FParent;
    property ElseList: TUsesList read FElseList;
    property Items[Index: Integer]: string read GetItems write SetItems; default;
    property SubList[Index: Integer]: TUsesList read GetSubList;
  end;

type
  TUsesInfo = class
  private
    FBegOfUses: Integer;
    FHasCompilerDirective: Boolean;
    FEndOfUses: Integer;
    FPosition: Integer;
    FUsesList: TUsesList;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function Exists: Boolean;
    procedure MoveLines(Value: Integer);
    property BegOfUses: Integer read FBegOfUses write FBegOfUses;
    property HasCompilerDirective: Boolean read FHasCompilerDirective write FHasCompilerDirective;
    property EndOfUses: Integer read FEndOfUses write FEndOfUses;
    property Position: Integer read FPosition write FPosition;
    property UsesList: TUsesList read FUsesList;
  end;

type
  TUsesInfoVisitor = class
  protected
    procedure VisitDirective(const Value: string); virtual; abstract;
    procedure VisitUnitName(var Value: string; Mode: TClosingMode); virtual; abstract;
  public
    procedure VisitList(List: TUsesList; Mode: TClosingMode = cmLast);
  end;

type
  TUsesInfoReader = class
  private
    FCurrent: TUsesList;
    FInDirectiveCnt: Integer;
    FSection: TUnitSection;
    FUsesInfo: array[TUnitSection] of TUsesInfo;
    function GetTarget(Index: TUnitSection): TUsesInfo;
    procedure SetTarget(Index: TUnitSection; Value: TUsesInfo);
  protected
    procedure AddUnitName(const Value: string);
    procedure BeginDirective(const Value: string);
    procedure ElseDirective(const Value: string);
    procedure EndDirective(const Value: string);
    procedure ExtendLastUnitName(const Value: string);
    function IsInDirective: Boolean;
    property Current: TUsesList read FCurrent write FCurrent;
    property Section: TUnitSection read FSection write FSection;
  public
    procedure LoadSource(const Source: string);
    property IntfUses: TUsesInfo index sInterface read GetTarget write SetTarget;
    property ImplUses: TUsesInfo index sImplementation read GetTarget write SetTarget;
  end;

implementation

uses
  SimpleParser.Lexer, SimpleParser.Lexer.Types;

constructor TUsesList.Create(AParent: TUsesList);
begin
  inherited Create;
  FParent := AParent;
  FData := TStringList.Create(True);
end;

destructor TUsesList.Destroy;
begin
  FData.Free;
  FElseList.Free;
  inherited Destroy;
end;

procedure TUsesList.AddUnitName(const Value: string);
begin
  FData.Add(Value);
end;

procedure TUsesList.Clear;
begin
  FData.Clear;
  FElseList.Free;
  FElseList := nil;
  FDirectiveBegin := '';
  FDirectiveEnd := '';
end;

function TUsesList.CreateSubList(const Value: string): TUsesList;
begin
  Result := TUsesList.Create(Self);
  Result.DirectiveBegin := Value;
  FData.AddObject('*', Result);
end;

function TUsesList.CreateElseList(const Value: string): TUsesList;
begin
  if FElseList = nil then begin
    FElseList := TUsesList.Create(FParent);
  end;
  FElseList.DirectiveBegin := Value;
  Result := FElseList;
end;

procedure TUsesList.Delete(Index: Integer);
begin
  FData.Delete(Index);
end;

procedure TUsesList.ExtendLastUnitName(const Value: string);
begin
  Items[Count - 1] := Items[Count - 1] + Value;
end;

function TUsesList.GetCount: Integer;
begin
  Result := FData.Count;
end;

function TUsesList.GetItems(Index: Integer): string;
begin
  Result := FData[Index];
end;

function TUsesList.GetSubList(Index: Integer): TUsesList;
begin
  Result := TUsesList(FData.Objects[Index]);
end;

function TUsesList.IsSubList(Index: Integer): Boolean;
begin
  Result := FData[Index] = '*';
end;

procedure TUsesList.SetItems(Index: Integer; const Value: string);
begin
  FData[Index] := Value;
end;

procedure TUsesInfoReader.AddUnitName(const Value: string);
begin
  Current.AddUnitName(Value);
end;

procedure TUsesInfoReader.BeginDirective(const Value: string);
begin
  Current := Current.CreateSubList(Value);
  Inc(FInDirectiveCnt);
end;

procedure TUsesInfoReader.ElseDirective(const Value: string);
begin
  Current := Current.CreateElseList(Value);
end;

procedure TUsesInfoReader.EndDirective(const Value: string);
begin
  Current.DirectiveEnd := Value;
  Current := Current.Parent;
  Dec(FInDirectiveCnt);
end;

procedure TUsesInfoReader.ExtendLastUnitName(const Value: string);
begin
  Current.ExtendLastUnitName(Value);
end;

function TUsesInfoReader.GetTarget(Index: TUnitSection): TUsesInfo;
begin
  Result := FUsesInfo[Index];
end;

function TUsesInfoReader.IsInDirective: Boolean;
begin
  Result := FInDirectiveCnt > 0;
end;

procedure TUsesInfoReader.LoadSource(const Source: string);
var
  directive: string;
  InUses: Boolean;
  parser: TmwPasLex;
  pendingClose: Boolean;
begin
  ImplUses.Clear;
  IntfUses.Clear;
  parser := TmwPasLex.Create;
  try
    parser.Origin := Source;
    Section := sInterface;
    InUses := False;
    pendingClose := False;
    parser.RunPos := 0;
    parser.NextNoSpace;
    while parser.TokenID <> ptNull do
    begin
      if parser.TokenID in [ptAnsiComment,ptCRLFCo,ptSlashesComment] then begin

      end
      else if parser.IsCompilerDirective then begin
        if InUses then begin
          directive := parser.Token;
          case parser.TokenID of
            ptIfDirect, ptIfDefDirect, ptIfNDefDirect, ptIfOptDirect,
            ptRegionDirect: begin
              BeginDirective(directive);
            end;
            ptElseDirect, ptElseIfDirect: begin
              ElseDirective(directive);
            end;
            ptEndIfDirect, ptIfEndDirect,
            ptEndRegionDirect: begin
              EndDirective(directive);
              if not IsInDirective and pendingClose then begin
                InUses := False;
                FUsesInfo[Section].EndOfUses := Parser.RunPos;
                if Section = sImplementation then
                  Break; // End of parsing
              end;
            end;
          end;
        end;
      end
      else begin
        case parser.TokenID of
          ptImplementation:
            begin
              Section := sImplementation;
              FUsesInfo[Section].Position := Parser.RunPos;
              InUses := False;
            end;
          ptUses:
            begin
              InUses := True;
              FUsesInfo[Section].BegOfUses := Parser.RunPos - Length('uses');
              Current := FUsesInfo[Section].UsesList;
              pendingClose := False;
            end;
        else
          // If it is after the unit identifier
          if InUses and not parser.IsCompilerDirective then
          begin
            case parser.TokenID of
              ptIdentifier: AddUnitName(parser.GetDottedIdentifierAtPos(True));
              ptIn,
              ptStringConst,
              ptBorComment: ExtendLastUnitName(' ' + parser.Token);
              ptComma: ;
            else
              if IsInDirective then
                pendingClose := true
              else begin
                InUses := False;
                FUsesInfo[Section].EndOfUses := Parser.RunPos;
                if Section = sImplementation then
                  Break; // End of parsing
              end; // Not comma
            end;
          end; // UsesFlag
        end;
      end;
      parser.NextNoSpace;
    end;
  finally
    parser.Free;
  end;
end;

procedure TUsesInfoReader.SetTarget(Index: TUnitSection; Value: TUsesInfo);
begin
  FUsesInfo[Index] := Value;
end;

constructor TUsesInfo.Create;
begin
  inherited Create;
  FUsesList := TUsesList.Create(nil);
end;

destructor TUsesInfo.Destroy;
begin
  FUsesList.Free;
  inherited Destroy;
end;

procedure TUsesInfo.Clear;
begin
  FUsesList.Clear;
  FBegOfUses := 0;
  FEndOfUses := 0;
  FHasCompilerDirective := False;
end;

function TUsesInfo.Exists: Boolean;
begin
  Result := UsesList.Count > 0;
end;

procedure TUsesInfo.MoveLines(Value: Integer);
begin
  FBegOfUses := FBegOfUses + Value;
  FEndOfUses := FEndOfUses + Value;
end;

procedure TUsesInfoVisitor.VisitList(List: TUsesList; Mode: TClosingMode = cmLast);
var
  I: Integer;
  last: TClosingMode;
  lastIndex: Integer;
  S: string;
begin
  if List = nil then Exit;

  VisitDirective(List.DirectiveBegin);

  lastIndex := List.Count - 1;
  for I := 0 to lastIndex do begin
    if I < lastIndex then
      last := cmNormal
    else
      last := Mode;
    if List.IsSubList(I) then begin
      VisitList(List.SubList[I], last);
    end
    else begin
      S := List[I];
      VisitUnitName(S, last);
      List[I] := S;
    end;
  end;
  VisitList(List.ElseList, Mode);
  VisitDirective(List.DirectiveEnd);
end;

end.
